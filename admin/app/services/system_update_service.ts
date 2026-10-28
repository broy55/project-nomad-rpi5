import logger from '@adonisjs/core/services/logger'
import { readFileSync, existsSync } from 'fs'
import { writeFile } from 'fs/promises'
import { join } from 'path'
import KVStore from '#models/kv_store'

interface UpdateStatus {
  stage: 'idle' | 'starting' | 'pulling' | 'pulled' | 'recreating' | 'complete' | 'error'
  progress: number
  message: string
  timestamp: string
}

export class SystemUpdateService {
  private static SHARED_DIR = '/app/update-shared'
  private static REQUEST_FILE = join(SystemUpdateService.SHARED_DIR, 'update-request')
  private static STATUS_FILE = join(SystemUpdateService.SHARED_DIR, 'update-status')
  private static LOG_FILE = join(SystemUpdateService.SHARED_DIR, 'update-log')

  /**
   * Requests a system update by creating a request file that the sidecar will detect
   */
  async requestUpdate(): Promise<{ success: boolean; message: string }> {
    // Updates are disabled until a safe upgrade procedure is available.
    return {
      success: false,
      message: 'In-app updates are disabled in the Raspberry Pi 5 edition. Your installation has not been changed.',
    }
  }

  getUpdateStatus(): UpdateStatus | null {
    try {
      if (!existsSync(SystemUpdateService.STATUS_FILE)) {
        return {
          stage: 'idle',
          progress: 0,
          message: 'No update in progress',
          timestamp: new Date().toISOString(),
        }
      }

      const statusContent = readFileSync(SystemUpdateService.STATUS_FILE, 'utf-8')
      return JSON.parse(statusContent) as UpdateStatus
    } catch (error) {
      logger.error('[SystemUpdateService]: Failed to read update status:', error)
      return null
    }
  }

  getUpdateLogs(): string {
    try {
      if (!existsSync(SystemUpdateService.LOG_FILE)) {
        return 'No update logs available'
      }

      return readFileSync(SystemUpdateService.LOG_FILE, 'utf-8')
    } catch (error) {
      logger.error('[SystemUpdateService]: Failed to read update logs:', error)
      return `Error reading logs: ${error.message}`
    }
  }

  /**
   * Check if the update sidecar is reachable (i.e. shared volume is mounted)
   */
  isSidecarAvailable(): boolean {
    try {
      return existsSync(SystemUpdateService.SHARED_DIR)
    } catch (error) {
      return false
    }
  }
}
