import { Job } from 'bullmq'
import { RunDownloadJobParams } from '../../types/downloads.js'
import { QueueService } from '#services/queue_service'
import { doResumableDownload } from '../utils/downloads.js'
import { createHash } from 'crypto'
import { DockerService } from '#services/docker_service'
import { ZimService } from '#services/zim_service'
import { MapService } from '#services/map_service'
import { dirname, join } from 'path'
import axios from 'axios'

export class RunDownloadJob {
  static get queue() {
    return 'downloads'
  }

  static get key() {
    return 'run-download'
  }

  static getJobId(url: string): string {
    return createHash('sha256').update(url).digest('hex').slice(0, 16)
  }

  async handle(job: Job) {
    const { url, filepath, timeout, allowedMimeTypes, forceNew, filetype, resourceMetadata } =
      job.data as RunDownloadJobParams

    const dockerService = new DockerService()
    const zimService = new ZimService(dockerService)
    let effectiveUrl = url
    let effectiveFilepath = filepath
    let effectiveResourceMetadata = resourceMetadata ? { ...resourceMetadata } : undefined

    const completeDownload = async (completedUrl: string, completedFilePath: string) => {
      try {
        if (effectiveResourceMetadata) {
          const { default: InstalledResource } = await import('#models/installed_resource')
          const { DateTime } = await import('luxon')
          const { getFileStatsIfExists, deleteFileIfExists } = await import('../utils/fs.js')
          const stats = await getFileStatsIfExists(completedFilePath)

          const oldEntry = await InstalledResource.query()
            .where('resource_id', effectiveResourceMetadata.resource_id)
            .where('resource_type', filetype as 'zim' | 'map')
            .first()
          const oldFilePath = oldEntry?.file_path ?? null

          await InstalledResource.updateOrCreate(
            { resource_id: effectiveResourceMetadata.resource_id, resource_type: filetype as 'zim' | 'map' },
            {
              version: effectiveResourceMetadata.version,
              collection_ref: effectiveResourceMetadata.collection_ref,
              url: completedUrl,
              file_path: completedFilePath,
              file_size_bytes: stats ? Number(stats.size) : null,
              installed_at: DateTime.now(),
            }
          )

          if (oldFilePath && oldFilePath !== completedFilePath) {
            try {
              await deleteFileIfExists(oldFilePath)
              console.log(`[RunDownloadJob] Deleted old file: ${oldFilePath}`)
            } catch (deleteError) {
              console.warn(`[RunDownloadJob] Failed to delete old file ${oldFilePath}:`, deleteError)
            }
          }
        }

        if (filetype === 'zim') {
          await zimService.downloadRemoteSuccessCallback([completedUrl], true)

          // Raspberry Pi optimization:
          // Kiwix ZIM archives are already searchable through Kiwix.
          // Do not automatically vector-embed large ZIM archives into Qdrant.
          // Normal Knowledge Base/document embedding remains enabled.
          console.log(`[RunDownloadJob] Skipping automatic RAG embedding for ZIM: ${completedFilePath}`)
        } else if (filetype === 'map') {
          const mapsService = new MapService()
          await mapsService.downloadRemoteSuccessCallback([completedUrl], false)
        }
      } catch (error) {
        console.error(`[RunDownloadJob] Error in download success callback for URL ${completedUrl}:`, error)
      }
      await job.updateProgress(100)
    }

    const runDownloadOnce = async () =>
      doResumableDownload({
        url: effectiveUrl,
        filepath: effectiveFilepath,
        timeout,
        allowedMimeTypes,
        forceNew,
        onProgress(progress) {
          const progressPercent = (progress.downloadedBytes / (progress.totalBytes || 1)) * 100
          job.updateProgress(Math.floor(progressPercent))
        },
        onComplete: () => completeDownload(effectiveUrl, effectiveFilepath),
      })

    try {
      await runDownloadOnce()
    } catch (error) {
      const status = axios.isAxiosError(error) ? error.response?.status : undefined
      const canResolveMovedSource = filetype === 'zim' && status === 404

      if (!canResolveMovedSource) {
        throw error
      }

      const resolved = await zimService.resolveRemoteDownloadTarget(
        effectiveUrl,
        effectiveResourceMetadata?.resource_id,
        effectiveResourceMetadata?.version
      )

      if (!resolved.changed) {
        throw error
      }

      effectiveUrl = resolved.url
      effectiveFilepath = join(dirname(effectiveFilepath), resolved.filename)
      if (effectiveResourceMetadata && resolved.version) {
        effectiveResourceMetadata.version = resolved.version
      }

      await job.updateData({
        ...job.data,
        url: effectiveUrl,
        filepath: effectiveFilepath,
        resourceMetadata: effectiveResourceMetadata,
        status: 'resolved_source_moved',
      })

      await runDownloadOnce()
    }

    return {
      url: effectiveUrl,
      filepath: effectiveFilepath,
    }
  }

  static async getByUrl(url: string): Promise<Job | undefined> {
    const queueService = new QueueService()
    const queue = queueService.getQueue(this.queue)
    const jobId = this.getJobId(url)
    return await queue.getJob(jobId)
  }

  static async dispatch(params: RunDownloadJobParams) {
    const queueService = new QueueService()
    const queue = queueService.getQueue(this.queue)
    const jobId = this.getJobId(params.url)

    try {
      const job = await queue.add(this.key, params, {
        jobId,
        attempts: 3,
        backoff: { type: 'exponential', delay: 2000 },
        removeOnComplete: true,
      })

      return {
        job,
        created: true,
        message: `Dispatched download job for URL ${params.url}`,
      }
    } catch (error) {
      if (error.message.includes('job already exists')) {
        const existing = await queue.getJob(jobId)
        return {
          job: existing,
          created: false,
          message: `Job already exists for URL ${params.url}`,
        }
      }
      throw error
    }
  }
}
