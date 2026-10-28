import KVStore from '#models/kv_store'
import { BenchmarkService } from '#services/benchmark_service'
import { MapService } from '#services/map_service'
import { OllamaService } from '#services/ollama_service'
import { SystemService } from '#services/system_service'
import { updateSettingSchema } from '#validators/settings'
import { inject } from '@adonisjs/core'
import type { HttpContext } from '@adonisjs/core/http'
import type { KVStoreKey } from '../../types/kv_store.js'

@inject()
export default class SettingsController {
  constructor(
    private systemService: SystemService,
    private mapService: MapService,
    private benchmarkService: BenchmarkService,
    private ollamaService: OllamaService
  ) {}

  async system({ inertia }: HttpContext) {
    const systemInfo = await this.systemService.getSystemInfo()
    return inertia.render('settings/system', {
      system: {
        info: systemInfo,
      },
    })
  }

  async apps({ inertia }: HttpContext) {
    const services = await this.systemService.getServices({ installedOnly: false })
    return inertia.render('settings/apps', {
      system: {
        services,
      },
    })
  }

  async legal({ inertia }: HttpContext) {
    return inertia.render('settings/legal')
  }

  async maps({ inertia }: HttpContext) {
    const baseAssetsExist = await this.mapService.ensureBaseAssets()
    const regionFiles = await this.mapService.listRegions()
    return inertia.render('settings/maps', {
      maps: {
        baseAssetsExist,
        regionFiles: regionFiles.files,
      },
    })
  }

  async models({ inertia }: HttpContext) {
    const availableModels = await this.ollamaService.getAvailableModels({
      sort: 'pulls',
      recommendedOnly: false,
      query: null,
      limit: 15,
    })
    const installedModels = await this.ollamaService.getModels(true)
    const chatSuggestionsEnabled = await KVStore.getValue('chat.suggestionsEnabled')
    const aiAssistantCustomName = await KVStore.getValue('ai.assistantCustomName')
    const aiAssistantContextPrompt = await KVStore.getValue('ai.assistantContextPrompt')
    const prewarmOnBoot = await KVStore.getValue('ollama.prewarmOnBoot')
    const keepModelWarm = await KVStore.getValue('ollama.keepModelWarm')
    const defaultChatModel = await KVStore.getValue('ollama.defaultChatModel')
    const prewarmDefaultChatModel = await KVStore.getValue('ollama.prewarmDefaultChatModel')
    const helperTextModel = await this.ollamaService.getConfiguredHelperTextModel()
    const helperEmbeddingModel = await this.ollamaService.getConfiguredEmbeddingModel()
    const prewarmHelperModels = await KVStore.getValue('ollama.prewarmHelperModels')
    return inertia.render('settings/models', {
      models: {
        availableModels: availableModels?.models || [],
        installedModels: installedModels || [],
        settings: {
          chatSuggestionsEnabled: chatSuggestionsEnabled ?? false,
          aiAssistantCustomName: aiAssistantCustomName ?? '',
          aiAssistantContextPrompt: aiAssistantContextPrompt ?? '',
          prewarmOnBoot: prewarmOnBoot ?? true,
          keepModelWarm: keepModelWarm ?? true,
          defaultChatModel: defaultChatModel ?? '',
          prewarmDefaultChatModel: prewarmDefaultChatModel ?? true,
          helperTextModel,
          helperEmbeddingModel,
          prewarmHelperModels: prewarmHelperModels ?? true,
        },
      },
    })
  }

  async update({ inertia }: HttpContext) {
    const updateInfo = await this.systemService.checkLatestVersion()
    return inertia.render('settings/update', {
      system: {
        updateAvailable: updateInfo.updateAvailable,
        latestVersion: updateInfo.latestVersion,
        currentVersion: updateInfo.currentVersion,
      },
    })
  }

  async zim({ inertia }: HttpContext) {
    return inertia.render('settings/zim/index')
  }

  async zimRemote({ inertia }: HttpContext) {
    return inertia.render('settings/zim/remote-explorer')
  }

  async benchmark({ inertia }: HttpContext) {
    const latestResult = await this.benchmarkService.getLatestResult()
    const status = this.benchmarkService.getStatus()
    return inertia.render('settings/benchmark', {
      benchmark: {
        latestResult,
        status: status.status,
        currentBenchmarkId: status.benchmarkId,
      },
    })
  }

  async getSetting({ request, response }: HttpContext) {
    const key = request.qs().key
    const value = await KVStore.getValue(key as KVStoreKey)
    return response.status(200).send({ key, value })
  }

  async updateSetting({ request, response }: HttpContext) {
    const reqData = await request.validateUsing(updateSettingSchema)
    await this.systemService.updateSetting(reqData.key, reqData.value)
    if (
      reqData.key === 'chat.lastModel' ||
      reqData.key === 'ollama.prewarmOnBoot' ||
      reqData.key === 'ollama.keepModelWarm' ||
      reqData.key === 'ollama.defaultChatModel' ||
      reqData.key === 'ollama.prewarmDefaultChatModel' ||
      reqData.key === 'ollama.helperTextModel' ||
      reqData.key === 'ollama.helperEmbeddingModel' ||
      reqData.key === 'ollama.prewarmHelperModels'
    ) {
      this.ollamaService.prewarmConfiguredModels().catch((error) => {
        console.error('Failed to prewarm configured models:', error)
      })
    }
    return response.status(200).send({ success: true, message: 'Setting updated successfully' })
  }
}
