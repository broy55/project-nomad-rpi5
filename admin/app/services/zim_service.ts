import {
  ListRemoteZimFilesResponse,
  RawRemoteZimFileEntry,
  RemoteZimFileEntry,
  ListZimDirectoryResponse,
  ZimDirectoryEntry,
  ZimRemoteSource,
} from '../../types/zim.js'
import axios from 'axios'
import { XMLParser } from 'fast-xml-parser'
import { isRawListRemoteZimFilesResponse, isRawRemoteZimFileEntry } from '../../util/zim.js'
import logger from '@adonisjs/core/services/logger'
import { DockerService } from './docker_service.js'
import { inject } from '@adonisjs/core'
import {
  deleteFileIfExists,
  ensureDirectoryExists,
  getFileStatsIfExists,
  listDirectoryContents,
  ZIM_STORAGE_PATH,
} from '../utils/fs.js'
import { join, resolve, sep } from 'path'
import { WikipediaOption, WikipediaState } from '../../types/downloads.js'
import type { ResolvedDownloadTarget } from '../../types/downloads.js'
import vine from '@vinejs/vine'
import { wikipediaOptionsFileSchema } from '#validators/curated_collections'
import WikipediaSelection from '#models/wikipedia_selection'
import InstalledResource from '#models/installed_resource'
import { RunDownloadJob } from '#jobs/run_download_job'
import { SERVICE_NAMES } from '../../constants/service_names.js'
import { CollectionManifestService } from './collection_manifest_service.js'
import type { CategoryWithStatus } from '../../types/collections.js'

const ZIM_MIME_TYPES = ['application/x-zim', 'application/x-openzim', 'application/octet-stream']
const WIKIPEDIA_OPTIONS_URL = 'https://raw.githubusercontent.com/eglische/project-nomad-rpi/refs/heads/main/collections/wikipedia.json'
const KIWIX_DOWNLOAD_HOST = 'download.kiwix.org'
const KIWIX_DIRECTORY_ROOT = 'https://download.kiwix.org/zim/'
const REMOTE_SOURCES: ZimRemoteSource[] = [
  {
    id: 'kiwix_catalog',
    name: 'Kiwix Catalog',
    kind: 'catalog',
    base_url: 'https://browse.library.kiwix.org/catalog/v2/entries',
    description: 'Searchable Kiwix catalog with titles, summaries, authors, and metadata. Best for normal discovery.',
    capabilities: ['search', 'metadata', 'download'],
  },
  {
    id: 'kiwix_directory',
    name: 'Kiwix Repository Browser',
    kind: 'directory',
    base_url: KIWIX_DIRECTORY_ROOT,
    description: 'Raw repository browser for the full Kiwix ZIM tree. Best when you want to explore categories and files directly.',
    capabilities: ['browse', 'download', 'manual selection'],
  },
  {
    id: 'manual_url',
    name: 'Direct URL Import',
    kind: 'manual',
    description: 'Paste a direct .zim URL from Kiwix or another trusted mirror when you already know the exact file you want.',
    capabilities: ['manual selection', 'download'],
  },
]

@inject()
export class ZimService {
  constructor(private dockerService: DockerService) { }

  listSources(): ZimRemoteSource[] {
    return REMOTE_SOURCES
  }

  async resolveRemoteDownloadTarget(
    url: string,
    resourceId?: string,
    preferredVersion?: string
  ): Promise<ResolvedDownloadTarget> {
    const parsedUrl = new URL(url)
    const filename = url.split('/').pop() || ''
    const parsedFilename = CollectionManifestService.parseZimFilename(filename)
    const effectiveResourceId = resourceId || parsedFilename?.resource_id
    const effectiveVersion = preferredVersion || parsedFilename?.version || null

    if (
      parsedUrl.hostname !== KIWIX_DOWNLOAD_HOST ||
      !parsedUrl.pathname.endsWith('.zim') ||
      !effectiveResourceId
    ) {
      return {
        url,
        filename,
        version: effectiveVersion,
        changed: false,
      }
    }

    const directoryUrl = new URL(
      `${parsedUrl.pathname.substring(0, parsedUrl.pathname.lastIndexOf('/') + 1)}`,
      `${parsedUrl.protocol}//${parsedUrl.host}`
    ).toString()

    try {
      const response = await axios.get(directoryUrl, {
        timeout: 15000,
        responseType: 'text',
      })
      const html = String(response.data)
      const escapedResourceId = effectiveResourceId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      const regex = new RegExp(`${escapedResourceId}_(\\d{4}-\\d{2})\\.zim`, 'g')
      const matches = new Set<string>()

      for (const match of html.matchAll(regex)) {
        matches.add(match[0])
      }

      if (matches.size === 0) {
        return {
          url,
          filename,
          version: effectiveVersion,
          changed: false,
        }
      }

      const available = Array.from(matches).sort((a, b) => a.localeCompare(b))
      const preferredFilename =
        effectiveVersion ? `${effectiveResourceId}_${effectiveVersion}.zim` : null
      const resolvedFilename = preferredFilename && matches.has(preferredFilename)
        ? preferredFilename
        : available[available.length - 1]

      const resolvedUrl = new URL(resolvedFilename, directoryUrl).toString()
      const resolvedParsed = CollectionManifestService.parseZimFilename(resolvedFilename)

      return {
        url: resolvedUrl,
        filename: resolvedFilename,
        version: resolvedParsed?.version || effectiveVersion,
        changed: resolvedUrl !== url,
      }
    } catch (error) {
      logger.warn(
        `[ZimService] Failed to resolve live Kiwix URL for ${url}: ${error instanceof Error ? error.message : error}`
      )
      return {
        url,
        filename,
        version: effectiveVersion,
        changed: false,
      }
    }
  }

  async list() {
    const dirPath = join(process.cwd(), ZIM_STORAGE_PATH)
    await ensureDirectoryExists(dirPath)

    const all = await listDirectoryContents(dirPath)
    const files = all.filter((item) => item.name.endsWith('.zim'))

    return {
      files,
    }
  }

  async listRemote({
    start,
    count,
    query,
  }: {
    start: number
    count: number
    query?: string
  }): Promise<ListRemoteZimFilesResponse> {
    const LIBRARY_BASE_URL = 'https://browse.library.kiwix.org/catalog/v2/entries'

    const res = await axios.get(LIBRARY_BASE_URL, {
      params: {
        start: start,
        count: count,
        lang: 'eng',
        ...(query ? { q: query } : {}),
      },
      // Kiwix browse requires an access-confirmation cookie.
      // Without it, the catalog endpoint returns an HTML confirmation
      // page instead of the expected OPDS/Atom XML response.
      headers: {
        Cookie: 'confirmed=yes',
      },
      responseType: 'text',
    })

    const data = res.data
    const parser = new XMLParser({
      ignoreAttributes: false,
      attributeNamePrefix: '',
      textNodeName: '#text',
    })
    const result = parser.parse(data)

    if (!isRawListRemoteZimFilesResponse(result)) {
      throw new Error('Invalid response format from remote library')
    }

    const entries = result.feed.entry
      ? Array.isArray(result.feed.entry)
        ? result.feed.entry
        : [result.feed.entry]
      : []

    const filtered = entries.filter((entry: any) => {
      return isRawRemoteZimFileEntry(entry)
    })

    const mapped: (RemoteZimFileEntry | null)[] = filtered.map((entry: RawRemoteZimFileEntry) => {
      const downloadLink = entry.link.find((link: any) => {
        return (
          typeof link === 'object' &&
          'rel' in link &&
          'length' in link &&
          'href' in link &&
          'type' in link &&
          link.type === 'application/x-zim'
        )
      })

      if (!downloadLink) {
        return null
      }

      // downloadLink['href'] will end with .meta4, we need to remove that to get the actual download URL
      const download_url = downloadLink['href'].substring(0, downloadLink['href'].length - 6)
      const file_name = download_url.split('/').pop() || `${entry.title}.zim`
      const sizeBytes = parseInt(downloadLink['length'], 10)

      return {
        id: entry.id,
        title: entry.title,
        updated: entry.updated,
        summary: entry.summary,
        size_bytes: sizeBytes || 0,
        download_url: download_url,
        author: entry.author.name,
        file_name: file_name,
      }
    })

    // Filter out any null entries (those without a valid download link)
    // or files that already exist in the local storage
    const existing = await this.list()
    const existingKeys = new Set(existing.files.map((file) => file.name))
    const withoutExisting = mapped.filter(
      (entry): entry is RemoteZimFileEntry => entry !== null && !existingKeys.has(entry.file_name)
    )

    return {
      items: withoutExisting,
      has_more: result.feed.totalResults > start,
      total_count: result.feed.totalResults,
    }
  }

  async browseRemoteDirectory({
    path = '',
    query,
  }: {
    path?: string
    query?: string
  }): Promise<ListZimDirectoryResponse> {
    const normalizedPath = path
      .split('/')
      .filter(Boolean)
      .join('/')
    const baseUrl = new URL(normalizedPath ? `${normalizedPath}/` : '', KIWIX_DIRECTORY_ROOT).toString()
    const response = await axios.get(baseUrl, {
      timeout: 15000,
      responseType: 'text',
    })
    const html = String(response.data)
    const entries: ZimDirectoryEntry[] = []
    const lines = html.split('\n')

    for (const line of lines) {
      const anchorMatch = line.match(/<a href="([^"]+)">([^<]+)<\/a>/)
      if (!anchorMatch) continue

      const [, href, rawName] = anchorMatch
      const name = rawName.trim()
      if (!href || !name || name === 'Parent Directory') continue

      const isDirectory = href.endsWith('/')
      if (!isDirectory && !href.endsWith('.zim')) continue

      const trailing = line.slice(line.indexOf(anchorMatch[0]) + anchorMatch[0].length)
      const metaMatch = trailing.match(/(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\s+([0-9.]+[KMGTP]?|-)/)
      const cleanName = name.replace(/\/$/, '')
      const nextPath = normalizedPath ? `${normalizedPath}/${cleanName}` : cleanName
      const fileUrl = new URL(href, baseUrl).toString()
      const inferred = isDirectory ? this.describeDirectory(cleanName) : this.describeFile(cleanName)

      entries.push({
        name: cleanName,
        path: nextPath,
        url: fileUrl,
        type: isDirectory ? 'directory' : 'file',
        size: !isDirectory && metaMatch?.[2] && metaMatch[2] !== '-' ? metaMatch[2] : undefined,
        last_modified: metaMatch?.[1],
        description: inferred.description,
        inferred_title: inferred.title,
      })
    }

    const filtered = !query
      ? entries
      : entries.filter((entry) => {
          const haystack = `${entry.name} ${entry.path} ${entry.inferred_title || ''} ${entry.description || ''}`.toLowerCase()
          return haystack.includes(query.toLowerCase())
        })

    filtered.sort((a, b) => {
      if (a.type !== b.type) return a.type === 'directory' ? -1 : 1
      return a.name.localeCompare(b.name)
    })

    const parentPath = normalizedPath.includes('/')
      ? normalizedPath.split('/').slice(0, -1).join('/')
      : normalizedPath
        ? ''
        : null

    return {
      source_id: 'kiwix_directory',
      current_path: normalizedPath,
      parent_path: parentPath,
      entries: filtered,
    }
  }

  async downloadRemote(url: string): Promise<{ filename: string; jobId?: string; resolvedUrl: string }> {
    const parsed = new URL(url)
    if (!parsed.pathname.endsWith('.zim')) {
      throw new Error(`Invalid ZIM file URL: ${url}. URL must end with .zim`)
    }

    const parsedSourceFilename = CollectionManifestService.parseZimFilename(url.split('/').pop() || '')
    const resolved = await this.resolveRemoteDownloadTarget(
      url,
      parsedSourceFilename?.resource_id,
      parsedSourceFilename?.version
    )

    const existing = await RunDownloadJob.getByUrl(resolved.url)
    if (existing) {
      throw new Error('A download for this URL is already in progress')
    }

    // Extract the filename from the URL
    const filename = resolved.filename
    if (!filename) {
      throw new Error('Could not determine filename from URL')
    }

    const filepath = join(process.cwd(), ZIM_STORAGE_PATH, filename)

    // Parse resource metadata for the download job
    const parsedResolvedFilename = CollectionManifestService.parseZimFilename(filename)
    const resourceMetadata = parsedResolvedFilename
      ? { resource_id: parsedResolvedFilename.resource_id, version: parsedResolvedFilename.version, collection_ref: null }
      : undefined

    // Dispatch a background download job
    const result = await RunDownloadJob.dispatch({
      url: resolved.url,
      filepath,
      timeout: 30000,
      allowedMimeTypes: ZIM_MIME_TYPES,
      forceNew: true,
      filetype: 'zim',
      resourceMetadata,
    })

    if (!result || !result.job) {
      throw new Error('Failed to dispatch download job')
    }

    logger.info(`[ZimService] Dispatched background download job for ZIM file: ${filename}`)

    return {
      filename,
      jobId: result.job.id,
      resolvedUrl: resolved.url,
    }
  }

  private describeDirectory(name: string): { title: string; description: string } {
    const title = name.replace(/[-_]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
    const descriptions: Record<string, string> = {
      wikipedia: 'Wikipedia snapshots in different sizes and language variants.',
      devdocs: 'Offline developer documentation exports generated from DevDocs content.',
      stack_exchange: 'Stack Exchange communities packaged as offline ZIM archives.',
      ted: 'TED talks and TED-Ed offline archives.',
      gutenberg: 'Project Gutenberg books grouped by subject and collection.',
    }
    return {
      title,
      description: descriptions[name] || 'Repository folder containing ZIM archives and versions.',
    }
  }

  private describeFile(name: string): { title: string; description: string } {
    const parsed = CollectionManifestService.parseZimFilename(name)
    if (!parsed) {
      return {
        title: name,
        description: 'ZIM archive available from the selected remote repository.',
      }
    }

    return {
      title: parsed.resource_id.replace(/[._-]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
      description: `Version ${parsed.version} ZIM archive from the selected remote repository.`,
    }
  }

  async listCuratedCategories(): Promise<CategoryWithStatus[]> {
    const manifestService = new CollectionManifestService()
    return manifestService.getCategoriesWithStatus()
  }

  async downloadCategoryTier(categorySlug: string, tierSlug: string): Promise<string[] | null> {
    const manifestService = new CollectionManifestService()
    const spec = await manifestService.getSpecWithFallback<import('../../types/collections.js').ZimCategoriesSpec>('zim_categories')
    if (!spec) {
      throw new Error('Could not load ZIM categories spec')
    }

    const category = spec.categories.find((c) => c.slug === categorySlug)
    if (!category) {
      throw new Error(`Category not found: ${categorySlug}`)
    }

    const tier = category.tiers.find((t) => t.slug === tierSlug)
    if (!tier) {
      throw new Error(`Tier not found: ${tierSlug}`)
    }

    const allResources = CollectionManifestService.resolveTierResources(tier, category.tiers)

    // Filter out already installed
    const installed = await InstalledResource.query().where('resource_type', 'zim')
    const installedIds = new Set(installed.map((r) => r.resource_id))
    const toDownload = allResources.filter((r) => !installedIds.has(r.id))

    if (toDownload.length === 0) return null

    const downloadFilenames: string[] = []

    for (const resource of toDownload) {
      const resolved = await this.resolveRemoteDownloadTarget(
        resource.url,
        resource.id,
        resource.version
      )
      const existingJob = await RunDownloadJob.getByUrl(resolved.url)
      if (existingJob) {
        logger.warn(`[ZimService] Download already in progress for ${resolved.url}, skipping.`)
        continue
      }

      const filename = resolved.filename
      if (!filename) continue

      downloadFilenames.push(filename)
      const filepath = join(process.cwd(), ZIM_STORAGE_PATH, filename)

      await RunDownloadJob.dispatch({
        url: resolved.url,
        filepath,
        timeout: 30000,
        allowedMimeTypes: ZIM_MIME_TYPES,
        forceNew: true,
        filetype: 'zim',
        resourceMetadata: {
          resource_id: resource.id,
          version: resource.version,
          collection_ref: categorySlug,
        },
      })
    }

    return downloadFilenames.length > 0 ? downloadFilenames : null
  }

  async downloadRemoteSuccessCallback(urls: string[], restart = true) {
    // Check if any URL is a Wikipedia download and handle it
    for (const url of urls) {
      if (url.includes('wikipedia_en_')) {
        await this.onWikipediaDownloadComplete(url, true)
      }
    }

    if (restart) {
      // Check if there are any remaining ZIM download jobs before restarting
      const { QueueService } = await import('./queue_service.js')
      const queueService = new QueueService()
      const queue = queueService.getQueue('downloads')

      // Get all active and waiting jobs
      const [activeJobs, waitingJobs] = await Promise.all([
        queue.getActive(),
        queue.getWaiting(),
      ])

      // Filter out completed jobs (progress === 100) to avoid race condition
      // where this job itself is still in the active queue
      const activeIncompleteJobs = activeJobs.filter((job) => {
        const progress = typeof job.progress === 'number' ? job.progress : 0
        return progress < 100
      })

      // Check if any remaining incomplete jobs are ZIM downloads
      const allJobs = [...activeIncompleteJobs, ...waitingJobs]
      const hasRemainingZimJobs = allJobs.some((job) => job.data.filetype === 'zim')

      if (hasRemainingZimJobs) {
        logger.info('[ZimService] Skipping container restart - more ZIM downloads pending')
      } else {
        // Restart KIWIX container to pick up new ZIM file
        logger.info('[ZimService] No more ZIM downloads pending - restarting KIWIX container')
        await this.dockerService
          .affectContainer(SERVICE_NAMES.KIWIX, 'restart')
          .catch((error) => {
            logger.error(`[ZimService] Failed to restart KIWIX container:`, error) // Don't stop the download completion, just log the error.
          })
      }
    }

    // Create InstalledResource entries for downloaded files
    for (const url of urls) {
      // Skip Wikipedia files (managed separately)
      if (url.includes('wikipedia_en_')) continue

      const filename = url.split('/').pop()
      if (!filename) continue

      const parsed = CollectionManifestService.parseZimFilename(filename)
      if (!parsed) continue

      const filepath = join(process.cwd(), ZIM_STORAGE_PATH, filename)
      const stats = await getFileStatsIfExists(filepath)

      try {
        const { DateTime } = await import('luxon')
        await InstalledResource.updateOrCreate(
          { resource_id: parsed.resource_id, resource_type: 'zim' },
          {
            version: parsed.version,
            url: url,
            file_path: filepath,
            file_size_bytes: stats ? Number(stats.size) : null,
            installed_at: DateTime.now(),
          }
        )
        logger.info(`[ZimService] Created InstalledResource entry for: ${parsed.resource_id}`)
      } catch (error) {
        logger.error(`[ZimService] Failed to create InstalledResource for ${filename}:`, error)
      }
    }
  }

  async delete(file: string): Promise<void> {
    let fileName = file
    if (!fileName.endsWith('.zim')) {
      fileName += '.zim'
    }

    const basePath = resolve(join(process.cwd(), ZIM_STORAGE_PATH))
    const fullPath = resolve(join(basePath, fileName))

    // Prevent path traversal — resolved path must stay within the storage directory
    if (!fullPath.startsWith(basePath + sep)) {
      throw new Error('Invalid filename')
    }

    const exists = await getFileStatsIfExists(fullPath)
    if (!exists) {
      throw new Error('not_found')
    }

    await deleteFileIfExists(fullPath)

    // Clean up InstalledResource entry
    const parsed = CollectionManifestService.parseZimFilename(fileName)
    if (parsed) {
      await InstalledResource.query()
        .where('resource_id', parsed.resource_id)
        .where('resource_type', 'zim')
        .delete()
      logger.info(`[ZimService] Deleted InstalledResource entry for: ${parsed.resource_id}`)
    }
  }

  // Wikipedia selector methods

  async getWikipediaOptions(): Promise<WikipediaOption[]> {
    try {
      const response = await axios.get(WIKIPEDIA_OPTIONS_URL)
      const data = response.data

      const validated = await vine.validate({
        schema: wikipediaOptionsFileSchema,
        data,
      })

      return validated.options
    } catch (error) {
      logger.error(`[ZimService] Failed to fetch Wikipedia options:`, error)
      throw new Error('Failed to fetch Wikipedia options')
    }
  }

  async getWikipediaSelection(): Promise<WikipediaSelection | null> {
    // Get the single row from wikipedia_selections (there should only ever be one)
    return WikipediaSelection.query().first()
  }

  async getWikipediaState(): Promise<WikipediaState> {
    const options = await this.getWikipediaOptions()
    const selection = await this.getWikipediaSelection()

    return {
      options,
      currentSelection: selection
        ? {
          optionId: selection.option_id,
          status: selection.status,
          filename: selection.filename,
          url: selection.url,
        }
        : null,
    }
  }

  async selectWikipedia(optionId: string): Promise<{ success: boolean; jobId?: string; message?: string }> {
    const options = await this.getWikipediaOptions()
    const selectedOption = options.find((opt) => opt.id === optionId)

    if (!selectedOption) {
      throw new Error(`Invalid Wikipedia option: ${optionId}`)
    }

    const currentSelection = await this.getWikipediaSelection()

    // If same as currently installed, no action needed
    if (currentSelection?.option_id === optionId && currentSelection.status === 'installed') {
      return { success: true, message: 'Already installed' }
    }

    // Handle "none" option - delete current Wikipedia file and update DB
    if (optionId === 'none') {
      if (currentSelection?.filename) {
        try {
          await this.delete(currentSelection.filename)
          logger.info(`[ZimService] Deleted Wikipedia file: ${currentSelection.filename}`)
        } catch (error) {
          // File might already be deleted, that's OK
          logger.warn(`[ZimService] Could not delete Wikipedia file (may already be gone): ${currentSelection.filename}`)
        }
      }

      // Update or create the selection record (always use first record)
      if (currentSelection) {
        currentSelection.option_id = 'none'
        currentSelection.url = null
        currentSelection.filename = null
        currentSelection.status = 'none'
        await currentSelection.save()
      } else {
        await WikipediaSelection.create({
          option_id: 'none',
          url: null,
          filename: null,
          status: 'none',
        })
      }

      // Restart Kiwix to reflect the change
      await this.dockerService
        .affectContainer(SERVICE_NAMES.KIWIX, 'restart')
        .catch((error) => {
          logger.error(`[ZimService] Failed to restart Kiwix after Wikipedia removal:`, error)
        })

      return { success: true, message: 'Wikipedia removed' }
    }

    // Start download for the new Wikipedia option
    if (!selectedOption.url) {
      throw new Error('Selected Wikipedia option has no download URL')
    }

    // Check if already downloading
    const existingJob = await RunDownloadJob.getByUrl(selectedOption.url)
    if (existingJob) {
      return { success: false, message: 'Download already in progress' }
    }

    // Extract filename from URL
    const filename = selectedOption.url.split('/').pop()
    if (!filename) {
      throw new Error('Could not determine filename from URL')
    }

    const filepath = join(process.cwd(), ZIM_STORAGE_PATH, filename)

    // Update or create selection record to show downloading status
    let selection: WikipediaSelection
    if (currentSelection) {
      currentSelection.option_id = optionId
      currentSelection.url = selectedOption.url
      currentSelection.filename = filename
      currentSelection.status = 'downloading'
      await currentSelection.save()
      selection = currentSelection
    } else {
      selection = await WikipediaSelection.create({
        option_id: optionId,
        url: selectedOption.url,
        filename: filename,
        status: 'downloading',
      })
    }

    // Dispatch download job
    const result = await RunDownloadJob.dispatch({
      url: selectedOption.url,
      filepath,
      timeout: 30000,
      allowedMimeTypes: ZIM_MIME_TYPES,
      forceNew: true,
      filetype: 'zim',
    })

    if (!result || !result.job) {
      // Revert status on failure to dispatch
      selection.option_id = currentSelection?.option_id || 'none'
      selection.url = currentSelection?.url || null
      selection.filename = currentSelection?.filename || null
      selection.status = currentSelection?.status || 'none'
      await selection.save()
      throw new Error('Failed to dispatch download job')
    }

    logger.info(`[ZimService] Started Wikipedia download for ${optionId}: ${filename}`)

    return {
      success: true,
      jobId: result.job.id,
      message: 'Download started',
    }
  }

  async onWikipediaDownloadComplete(url: string, success: boolean): Promise<void> {
    const selection = await this.getWikipediaSelection()

    if (!selection || selection.url !== url) {
      logger.warn(`[ZimService] Wikipedia download complete callback for unknown URL: ${url}`)
      return
    }

    if (success) {
      // Update status to installed
      selection.status = 'installed'
      await selection.save()

      logger.info(`[ZimService] Wikipedia download completed successfully: ${selection.filename}`)

      // Delete the old Wikipedia file if it exists and is different
      // We need to find what was previously installed
      const existingFiles = await this.list()
      const wikipediaFiles = existingFiles.files.filter((f) =>
        f.name.startsWith('wikipedia_en_') && f.name !== selection.filename
      )

      for (const oldFile of wikipediaFiles) {
        try {
          await this.delete(oldFile.name)
          logger.info(`[ZimService] Deleted old Wikipedia file: ${oldFile.name}`)
        } catch (error) {
          logger.warn(`[ZimService] Could not delete old Wikipedia file: ${oldFile.name}`, error)
        }
      }
    } else {
      // Download failed - keep the selection record but mark as failed
      selection.status = 'failed'
      await selection.save()
      logger.error(`[ZimService] Wikipedia download failed for: ${selection.filename}`)
    }
  }
}
