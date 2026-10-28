import { useState, useCallback, useEffect, useRef, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import ChatSidebar from './ChatSidebar'
import ChatInterface from './ChatInterface'
import StyledModal from '../StyledModal'
import api from '~/lib/api'
import { formatBytes } from '~/lib/util'
import { useModals } from '~/context/ModalContext'
import { useNotifications } from '~/context/NotificationContext'
import { ChatMessage } from '../../../types/chat'
import classNames from '~/lib/classNames'
import { IconX } from '@tabler/icons-react'
import { useSystemSetting } from '~/hooks/useSystemSetting'
import useDownloads from '~/hooks/useDownloads'
import useEmbedJobs from '~/hooks/useEmbedJobs'

const DEFAULT_HELPER_TEXT_MODEL = 'qwen2.5:3b'
const DEFAULT_HELPER_EMBEDDING_MODEL = 'nomic-embed-text:v1.5'

interface ChatProps {
  enabled: boolean
  isInModal?: boolean
  onClose?: () => void
  suggestionsEnabled?: boolean
  streamingEnabled?: boolean
}

export default function Chat({
  enabled,
  isInModal,
  onClose,
  suggestionsEnabled = false,
  streamingEnabled = true,
}: ChatProps) {
  const queryClient = useQueryClient()
  const { openModal, closeAllModals } = useModals()
  const { addNotification } = useNotifications()
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [selectedModel, setSelectedModel] = useState<string>('')
  const [activeChatModel, setActiveChatModel] = useState<string>('')
  const [pendingLoadModel, setPendingLoadModel] = useState<string | null>(null)
  const [loadStartedAt, setLoadStartedAt] = useState<number | null>(null)
  const [loadBaselineGpuBytes, setLoadBaselineGpuBytes] = useState<number | null>(null)
  const [loadMinObservedGpuBytes, setLoadMinObservedGpuBytes] = useState<number | null>(null)
  const [isStreamingResponse, setIsStreamingResponse] = useState(false)
  const [isGenerating, setIsGenerating] = useState(false)
  const streamAbortRef = useRef<AbortController | null>(null)

  // Fetch all sessions
  const { data: sessions = [] } = useQuery({
    queryKey: ['chatSessions'],
    queryFn: () => api.getChatSessions(),
    enabled,
    select: (data) =>
      data?.map((s) => ({
        id: s.id,
        title: s.title,
        model: s.model || undefined,
        folder: s.folder,
        sortOrder: s.sortOrder,
        timestamp: new Date(s.timestamp),
        lastMessage: s.lastMessage || undefined,
      })) || [],
  })

  const activeSession = sessions.find((s) => s.id === activeSessionId)

  const { data: lastModelSetting } = useSystemSetting({ key: 'chat.lastModel', enabled })
  const { data: chatFoldersSetting } = useSystemSetting({ key: 'chat.folders', enabled })
  const { data: defaultChatModelSetting } = useSystemSetting({ key: 'ollama.defaultChatModel', enabled })
  const { data: helperTextModelSetting } = useSystemSetting({ key: 'ollama.helperTextModel', enabled })
  const { data: helperEmbeddingModelSetting } = useSystemSetting({ key: 'ollama.helperEmbeddingModel', enabled })

  const { data: installedModels = [], isLoading: isLoadingModels } = useQuery({
    queryKey: ['installedModels'],
    queryFn: () => api.getInstalledModels(),
    enabled,
    refetchInterval: 5000,
    select: (data) => data || [],
  })
  const { data: runtimeStatus } = useQuery({
    queryKey: ['ollamaRuntimeStatus'],
    queryFn: () => api.getOllamaRuntimeStatus(),
    enabled,
    refetchInterval: pendingLoadModel ? 500 : 2000,
  })
  const { data: systemActivity } = useQuery({
    queryKey: ['system-activity', 'chat'],
    queryFn: () => api.getSystemActivity(),
    enabled,
    refetchInterval: 2000,
  })
  const { data: activeDownloads = [] } = useDownloads({ enabled })
  const { data: activeEmbedJobs = [] } = useEmbedJobs({ enabled })

  const { data: chatSuggestions, isLoading: chatSuggestionsLoading } = useQuery<string[]>({
    queryKey: ['chatSuggestions'],
    queryFn: async ({ signal }) => {
      const res = await api.getChatSuggestions(signal)
      return res ?? []
    },
    enabled: suggestionsEnabled && !activeSessionId,
    refetchOnWindowFocus: false,
    refetchOnMount: false,
  })

  const rewriteModelAvailable = useMemo(() => {
    const helperTextModel =
      typeof helperTextModelSetting?.value === 'string' && helperTextModelSetting.value
        ? helperTextModelSetting.value
        : 'qwen2.5:3b'
    return installedModels.some((model) => model.name === helperTextModel)
  }, [installedModels, helperTextModelSetting])

  const rewriteModelName = useMemo(() => {
    return typeof helperTextModelSetting?.value === 'string' && helperTextModelSetting.value
      ? helperTextModelSetting.value
      : 'qwen2.5:3b'
  }, [helperTextModelSetting])

  const folders = useMemo(() => {
    const raw = chatFoldersSetting?.value
    if (!raw || typeof raw !== 'string') {
      return [] as string[]
    }

    try {
      const parsed = JSON.parse(raw)
      if (!Array.isArray(parsed)) {
        return []
      }

      return parsed
        .filter((item): item is string => typeof item === 'string')
        .map((item) => item.trim())
        .filter(Boolean)
    } catch {
      return []
    }
  }, [chatFoldersSetting])

  const backgroundInferenceWarning = useMemo(() => {
    const impactfulDownloads = activeDownloads.filter((job) => job.progress < 100)
    const activeEmbeds = activeEmbedJobs.filter((job) => job.progress < 100)

    if (impactfulDownloads.length === 0 && activeEmbeds.length === 0) {
      return null
    }

    const parts: string[] = []
    if (activeEmbeds.length > 0) {
      parts.push(`${activeEmbeds.length} embedding job${activeEmbeds.length === 1 ? '' : 's'}`)
    }
    if (impactfulDownloads.length > 0) {
      parts.push(`${impactfulDownloads.length} download${impactfulDownloads.length === 1 ? '' : 's'}`)
    }

    return `${parts.join(' and ')} running in the background may slow replies.`
  }, [activeDownloads, activeEmbedJobs])

  const deleteAllSessionsMutation = useMutation({
    mutationFn: () => api.deleteAllChatSessions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
      setActiveSessionId(null)
      setMessages([])
      closeAllModals()
    },
  })

  const saveFolders = useCallback(
    async (nextFolders: string[]) => {
      await api.updateSetting('chat.folders', JSON.stringify(nextFolders))
      await queryClient.invalidateQueries({ queryKey: ['system-setting', 'chat.folders'] })
    },
    [queryClient]
  )

  const chatMutation = useMutation({
    mutationFn: (request: {
      model: string
      messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }>
      sessionId?: number
    }) => api.sendChatMessage({ ...request, stream: false }),
    onSuccess: async (data) => {
      if (!data || !activeSessionId) {
        throw new Error('No response from Ollama')
      }

      // Add assistant message
      const assistantMessage: ChatMessage = {
        id: `msg-${Date.now()}-assistant`,
        role: 'assistant',
        content: data.message?.content || 'Sorry, I could not generate a response.',
        timestamp: new Date(),
      }

      setMessages((prev) => [...prev, assistantMessage])

      // Refresh sessions to pick up backend-persisted messages and title
      queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
      setTimeout(() => queryClient.invalidateQueries({ queryKey: ['chatSessions'] }), 3000)
    },
    onError: (error) => {
      console.error('Error sending message:', error)
      const errorMessage: ChatMessage = {
        id: `msg-${Date.now()}-error`,
        role: 'assistant',
        content: 'Sorry, there was an error processing your request. Please try again.',
        timestamp: new Date(),
      }
      setMessages((prev) => [...prev, errorMessage])
    },
  })

  const loadModelMutation = useMutation({
    onMutate: (model) => {
      setPendingLoadModel(model)
      setLoadStartedAt(Date.now())
      setLoadBaselineGpuBytes(runtimeStatus?.gpuMemoryUsedBytes ?? 0)
      setLoadMinObservedGpuBytes(runtimeStatus?.gpuMemoryUsedBytes ?? 0)
    },
    mutationFn: async (model: string) => {
      const response = await api.loadOllamaModel(model)
      if (!response?.success) {
        throw new Error(response?.message || 'Failed to load model')
      }
      await api.updateSetting('chat.lastModel', model)
      return response
    },
    onSuccess: async (_response, model) => {
      setPendingLoadModel(null)
      setLoadStartedAt(null)
      setLoadBaselineGpuBytes(null)
      setLoadMinObservedGpuBytes(null)
      setActiveChatModel(model)
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['system-setting', 'chat.lastModel'] }),
        queryClient.invalidateQueries({ queryKey: ['ollamaRuntimeStatus'] }),
      ])
      addNotification({
        type: 'success',
        message: `${model} is now loaded for chat.`,
      })
    },
    onError: (error) => {
      setPendingLoadModel(null)
      setLoadStartedAt(null)
      setLoadBaselineGpuBytes(null)
      setLoadMinObservedGpuBytes(null)
      addNotification({
        type: 'error',
        message: error instanceof Error ? error.message : 'Failed to load chat model.',
      })
    },
  })

  const selectedInstalledModel = useMemo(
    () => installedModels.find((model) => model.name === selectedModel),
    [installedModels, selectedModel]
  )

  const selectedLoadedModel = useMemo(
    () => runtimeStatus?.loadedModels.find((model) => model.name === selectedModel),
    [runtimeStatus, selectedModel]
  )

  const helperModelNames = useMemo(() => {
    const helperNames = new Set<string>()
    if (typeof helperTextModelSetting?.value === 'string' && helperTextModelSetting.value) {
      helperNames.add(helperTextModelSetting.value)
    } else {
      helperNames.add(DEFAULT_HELPER_TEXT_MODEL)
    }

    if (typeof helperEmbeddingModelSetting?.value === 'string' && helperEmbeddingModelSetting.value) {
      helperNames.add(helperEmbeddingModelSetting.value)
    } else {
      helperNames.add(DEFAULT_HELPER_EMBEDDING_MODEL)
    }

    return helperNames
  }, [helperEmbeddingModelSetting, helperTextModelSetting])

  const activeLoadedChatModel = useMemo(() => {
    const loadedNonHelperModels =
      runtimeStatus?.loadedModels.filter((model) => !helperModelNames.has(model.name)) || []

    if (loadedNonHelperModels.length === 0) {
      return ''
    }

    if (pendingLoadModel) {
      const pendingLoaded = loadedNonHelperModels.find((model) => model.name === pendingLoadModel)
      if (pendingLoaded) {
        return pendingLoaded.name
      }
    }

    const lastModel = typeof lastModelSetting?.value === 'string' ? lastModelSetting.value : ''
    const lastLoaded = loadedNonHelperModels.find((model) => model.name === lastModel)
    if (lastLoaded) {
      return lastLoaded.name
    }

    return loadedNonHelperModels[0].name
  }, [helperModelNames, lastModelSetting, pendingLoadModel, runtimeStatus])

  useEffect(() => {
    if (!pendingLoadModel) {
      return
    }

    const currentGpuBytes = runtimeStatus?.gpuMemoryUsedBytes
    if (typeof currentGpuBytes !== 'number') {
      return
    }

    setLoadMinObservedGpuBytes((previous) => {
      if (previous === null) {
        return currentGpuBytes
      }
      return Math.min(previous, currentGpuBytes)
    })
  }, [pendingLoadModel, runtimeStatus])

  const activeModelDownload = useMemo(
    () =>
      systemActivity?.modelDownloads.activeJobs.find((job) => job.label === selectedModel) ||
      systemActivity?.modelDownloads.queuedJobs.find((job) => job.label === selectedModel),
    [selectedModel, systemActivity]
  )

  const modelLoadingStatus = useMemo(() => {
    if (!selectedModel) {
      return null
    }

    if (activeModelDownload) {
      return {
        text: `Downloading ${selectedModel} (${Math.max(0, Math.min(100, Math.round(activeModelDownload.progress || 0)))}%)`,
        progress: Math.max(0, Math.min(100, Math.round(activeModelDownload.progress || 0))),
        mode: 'determinate' as const,
      }
    }

    if (!(isStreamingResponse || chatMutation.isPending || loadModelMutation.isPending)) {
      return null
    }

    if (!selectedInstalledModel || selectedLoadedModel) {
      return null
    }

    const elapsedMs = loadStartedAt ? Date.now() - loadStartedAt : 0
    const unloadingOldModel =
      !!activeLoadedChatModel && activeLoadedChatModel !== selectedModel
    const currentGpuBytes = runtimeStatus?.gpuMemoryUsedBytes ?? loadBaselineGpuBytes ?? 0
    const baselineGpuBytes = loadBaselineGpuBytes ?? currentGpuBytes
    const lowWaterGpuBytes = loadMinObservedGpuBytes ?? Math.min(baselineGpuBytes, currentGpuBytes)
    const expectedModelBytes = Math.max(
      selectedInstalledModel.size || 0,
      selectedLoadedModel?.sizeVramBytes || 0
    )

    let progress = unloadingOldModel
      ? Math.max(8, Math.min(38, 8 + Math.round(elapsedMs / 180)))
      : Math.max(42, Math.min(92, 42 + Math.round(elapsedMs / 180)))

    if (!unloadingOldModel && expectedModelBytes > 0) {
      const growthBytes = Math.max(0, currentGpuBytes - lowWaterGpuBytes)
      const fillRatio = Math.max(0, Math.min(1, growthBytes / expectedModelBytes))
      const vramProgress = Math.max(
        45,
        Math.min(94, 45 + Math.round(fillRatio * 49))
      )
      progress = Math.max(progress, vramProgress)
    }

    return {
      text: unloadingOldModel
        ? `Unloading ${activeLoadedChatModel} and preparing ${selectedModel}...`
        : `Loading ${selectedModel} for inference...`,
      progress,
      mode: 'determinate' as const,
    }
  }, [
    activeLoadedChatModel,
    activeModelDownload,
    chatMutation.isPending,
    loadBaselineGpuBytes,
    loadMinObservedGpuBytes,
    loadStartedAt,
    loadModelMutation.isPending,
    isStreamingResponse,
    runtimeStatus,
    selectedInstalledModel,
    selectedLoadedModel,
    selectedModel,
  ])

  // Set default model: prefer last used model, fall back to first installed if last model not available
  useEffect(() => {
    if (installedModels.length > 0 && !selectedModel) {
      const lastModel = lastModelSetting?.value as string | undefined
      const defaultModel = defaultChatModelSetting?.value as string | undefined
      const currentModel =
        lastModel && installedModels.some((m) => m.name === lastModel)
          ? lastModel
          : defaultModel && installedModels.some((m) => m.name === defaultModel)
            ? defaultModel
            : installedModels[0].name

      setSelectedModel(currentModel)
      setActiveChatModel(currentModel)
    }
  }, [installedModels, selectedModel, lastModelSetting, defaultChatModelSetting])

  useEffect(() => {
    const lastModel = typeof lastModelSetting?.value === 'string' ? lastModelSetting.value : ''
    const runtimeModel = activeLoadedChatModel || lastModel
    if (runtimeModel && installedModels.some((model) => model.name === runtimeModel)) {
      setActiveChatModel(runtimeModel)
      if (!selectedModel) {
        setSelectedModel(runtimeModel)
      }
    }
  }, [activeLoadedChatModel, installedModels, lastModelSetting, selectedModel])

  const handleStopGeneration = useCallback(() => {
    streamAbortRef.current?.abort()
  }, [])

  const handleNewChat = useCallback(() => {
    // Just clear the active session and messages - don't create a session yet
    setActiveSessionId(null)
    setMessages([])
  }, [])

  const handleClearHistory = useCallback(() => {
    openModal(
      <StyledModal
        title="Clear All Chat History?"
        onConfirm={() => deleteAllSessionsMutation.mutate()}
        onCancel={closeAllModals}
        open={true}
        confirmText="Clear All"
        cancelText="Cancel"
        confirmVariant="danger"
      >
        <p className="text-gray-700">
          Are you sure you want to delete all chat sessions? This action cannot be undone and all
          conversations will be permanently deleted.
        </p>
      </StyledModal>,
      'confirm-clear-history-modal'
    )
  }, [openModal, closeAllModals, deleteAllSessionsMutation])

  const handleRenameSession = useCallback(
    async (sessionId: string, title: string) => {
      await api.updateChatSession(sessionId, { title })
      await queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
    },
    [queryClient]
  )

  const handleDeleteSession = useCallback(
    async (sessionId: string) => {
      const session = sessions.find((item) => item.id === sessionId)
      if (!session) return

      openModal(
        <StyledModal
          title="Delete Chat?"
          onConfirm={async () => {
            await api.deleteChatSession(sessionId)
            if (activeSessionId === sessionId) {
              setActiveSessionId(null)
              setMessages([])
            }
            await queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
            closeAllModals()
          }}
          onCancel={closeAllModals}
          open={true}
          confirmText="Delete"
          cancelText="Cancel"
          confirmVariant="danger"
        >
          <p className="text-gray-700">
            Delete <span className="font-semibold">{session.title}</span>? This cannot be undone.
          </p>
        </StyledModal>,
        'confirm-delete-chat-modal'
      )
    },
    [activeSessionId, closeAllModals, openModal, queryClient, sessions]
  )

  const handleCreateFolder = useCallback(
    async (name: string) => {
      const trimmed = name.trim()
      if (!trimmed) return
      if (folders.includes(trimmed)) {
        addNotification({ type: 'error', message: 'A folder with that name already exists.' })
        return
      }
      await saveFolders([...folders, trimmed])
    },
    [addNotification, folders, saveFolders]
  )

  const handleRenameFolder = useCallback(
    async (currentName: string, nextName: string) => {
      const trimmed = nextName.trim()
      if (!trimmed || currentName === trimmed) return
      if (folders.includes(trimmed)) {
        addNotification({ type: 'error', message: 'A folder with that name already exists.' })
        return
      }

      await saveFolders(folders.map((folder) => (folder === currentName ? trimmed : folder)))

      const affected = sessions.filter((session) => session.folder === currentName)
      await Promise.all(
        affected.map((session, index) =>
          api.updateChatSession(session.id, {
            folder: trimmed,
            sortOrder: session.sortOrder ?? index,
          })
        )
      )
      await queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
    },
    [addNotification, folders, queryClient, saveFolders, sessions]
  )

  const handleDeleteFolder = useCallback(
    async (name: string) => {
      const affected = sessions.filter((session) => session.folder === name)

      openModal(
        <StyledModal
          title="Delete Folder?"
          onConfirm={async () => {
            await saveFolders(folders.filter((folder) => folder !== name))
            await Promise.all(
              affected.map((session, index) =>
                api.updateChatSession(session.id, {
                  folder: null,
                  sortOrder: index,
                })
              )
            )
            await queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
            closeAllModals()
          }}
          onCancel={closeAllModals}
          open={true}
          confirmText="Delete Folder"
          cancelText="Cancel"
          confirmVariant="danger"
        >
          <p className="text-gray-700">
            Delete <span className="font-semibold">{name}</span>? Chats inside it will be moved back
            to Ungrouped.
          </p>
        </StyledModal>,
        'confirm-delete-folder-modal'
      )
    },
    [closeAllModals, folders, openModal, queryClient, saveFolders, sessions]
  )

  const handleMoveSessionToFolder = useCallback(
    async (sessionId: string, folder: string | null) => {
      const targetSessions = sessions
        .filter((session) => (session.folder ?? null) === folder && session.id !== sessionId)
        .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))

      await api.updateChatSession(sessionId, {
        folder,
        sortOrder: targetSessions.length,
      })
      await queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
    },
    [queryClient, sessions]
  )

  const handleSessionSelect = useCallback(
    async (sessionId: string) => {
      // Cancel any ongoing suggestions fetch
      queryClient.cancelQueries({ queryKey: ['chatSuggestions'] })

      setActiveSessionId(sessionId)
      // Load messages for this session
      const sessionData = await api.getChatSession(sessionId)
      if (sessionData?.messages) {
        setMessages(
          sessionData.messages.map((m) => ({
            id: m.id,
            role: m.role,
            content: m.content,
            timestamp: new Date(m.timestamp),
          }))
        )
      } else {
        setMessages([])
      }

      // Set the model to match the session's model if it exists and is available
      if (sessionData?.model) {
        setSelectedModel(sessionData.model)
      }
    },
    [installedModels, queryClient]
  )

  const currentChatModel = activeChatModel || selectedModel || 'llama3.2'

  const handleSendMessage = useCallback(
    async (content: string) => {
      let sessionId = activeSessionId

      // Create a new session if none exists
      if (!sessionId) {
        const newSession = await api.createChatSession('New Chat', currentChatModel, null, sessions.length)
        if (newSession) {
          sessionId = newSession.id
          setActiveSessionId(sessionId)
          queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
        } else {
          return
        }
      }

      // Add user message to UI
      const userMessage: ChatMessage = {
        id: `msg-${Date.now()}`,
        role: 'user',
        content,
        timestamp: new Date(),
      }

      setMessages((prev) => [...prev, userMessage])

      const chatMessages = [
        ...messages.map((m) => ({ role: m.role, content: m.content })),
        { role: 'user' as const, content },
      ]

      if (streamingEnabled !== false) {
        // Streaming path
        const abortController = new AbortController()
        streamAbortRef.current = abortController

        setIsStreamingResponse(true)
        setIsGenerating(true)

        const assistantMsgId = `msg-${Date.now()}-assistant`
        let isFirstChunk = true
        let fullContent = ''
        let thinkingContent = ''
        let isThinkingPhase = true
        let thinkingStartTime: number | null = null
        let thinkingDuration: number | null = null

        try {
          await api.streamChatMessage(
            { model: currentChatModel, messages: chatMessages, stream: true, sessionId: sessionId ? Number(sessionId) : undefined },
            (chunkContent, chunkThinking, done) => {
              if (chunkThinking.length > 0 && thinkingStartTime === null) {
                thinkingStartTime = Date.now()
              }
              if (isFirstChunk) {
                isFirstChunk = false
                setIsStreamingResponse(false)
                setMessages((prev) => [
                  ...prev,
                  {
                    id: assistantMsgId,
                    role: 'assistant',
                    content: chunkContent,
                    thinking: chunkThinking,
                    timestamp: new Date(),
                    isStreaming: true,
                    isThinking: chunkThinking.length > 0 && chunkContent.length === 0,
                    thinkingDuration: undefined,
                  },
                ])
              } else {
                if (isThinkingPhase && chunkContent.length > 0) {
                  isThinkingPhase = false
                  if (thinkingStartTime !== null) {
                    thinkingDuration = Math.max(1, Math.round((Date.now() - thinkingStartTime) / 1000))
                  }
                }
                setMessages((prev) =>
                  prev.map((m) =>
                    m.id === assistantMsgId
                      ? {
                        ...m,
                        content: m.content + chunkContent,
                        thinking: (m.thinking ?? '') + chunkThinking,
                        isStreaming: !done,
                        isThinking: isThinkingPhase,
                        thinkingDuration: thinkingDuration ?? undefined,
                      }
                      : m
                  )
                )
              }
              fullContent += chunkContent
              thinkingContent += chunkThinking
            },
            abortController.signal
          )
        } catch (error: any) {
          if (error?.name !== 'AbortError') {
            setMessages((prev) => {
              const hasAssistantMsg = prev.some((m) => m.id === assistantMsgId)
              if (hasAssistantMsg) {
                return prev.map((m) =>
                  m.id === assistantMsgId ? { ...m, isStreaming: false } : m
                )
              }
              return [
                ...prev,
                {
                  id: assistantMsgId,
                  role: 'assistant',
                  content: 'Sorry, there was an error processing your request. Please try again.',
                  timestamp: new Date(),
                },
              ]
            })
          }
        } finally {
          setIsStreamingResponse(false)
          setIsGenerating(false)
          streamAbortRef.current = null
        }

        if (fullContent && sessionId) {
          // Ensure the streaming cursor is removed
          setMessages((prev) =>
            prev.map((m) =>
              m.id === assistantMsgId ? { ...m, isStreaming: false } : m
            )
          )

          // Refresh sessions to pick up backend-persisted messages and title
          queryClient.invalidateQueries({ queryKey: ['chatSessions'] })
          setTimeout(() => queryClient.invalidateQueries({ queryKey: ['chatSessions'] }), 3000)
        }
      } else {
        // Non-streaming (legacy) path
        chatMutation.mutate({
          model: currentChatModel,
          messages: chatMessages,
          sessionId: sessionId ? Number(sessionId) : undefined,
        })
      }
    },
    [activeSessionId, messages, currentChatModel, chatMutation, queryClient, sessions.length, streamingEnabled]
  )

  return (
    <div
      className={classNames(
        'flex border border-gray-200 overflow-hidden shadow-sm w-full',
        isInModal ? 'h-full rounded-lg' : 'h-screen'
      )}
    >
      <ChatSidebar
        sessions={sessions}
        folders={folders}
        activeSessionId={activeSessionId}
        onSessionSelect={handleSessionSelect}
        onNewChat={handleNewChat}
        onClearHistory={handleClearHistory}
        onRenameSession={handleRenameSession}
        onDeleteSession={handleDeleteSession}
        onCreateFolder={handleCreateFolder}
        onRenameFolder={handleRenameFolder}
        onDeleteFolder={handleDeleteFolder}
        onMoveSessionToFolder={handleMoveSessionToFolder}
        isInModal={isInModal}
      />
      <div className="flex-1 flex flex-col min-h-0">
        <div className="px-6 py-3 border-b border-gray-200 bg-gray-50 flex items-center justify-between h-[75px] flex-shrink-0">
          <h2 className="text-lg font-semibold text-gray-800">
            {activeSession?.title || 'New Chat'}
          </h2>
          <div className="flex items-center gap-4">
            {modelLoadingStatus && (
              <div className="min-w-[16rem] rounded-xl border border-sky-200/80 bg-sky-100/70 px-3 py-2 text-xs font-medium text-sky-950 shadow-sm backdrop-blur-sm">
                <div className="flex items-center justify-between gap-3">
                  <span>{modelLoadingStatus.text}</span>
                  {modelLoadingStatus.mode === 'determinate' && (
                    <span>{modelLoadingStatus.progress}%</span>
                  )}
                </div>
                <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-sky-200/80">
                  {modelLoadingStatus.mode === 'determinate' ? (
                    <div
                      className="h-full rounded-full bg-sky-500 transition-all duration-500"
                      style={{ width: `${modelLoadingStatus.progress}%` }}
                    />
                  ) : (
                    <div className="h-full w-1/3 rounded-full bg-sky-500/90 animate-[pulse_1.2s_ease-in-out_infinite]" />
                  )}
                </div>
              </div>
            )}
            {backgroundInferenceWarning && (
              <div className="max-w-sm rounded-xl border border-amber-200/80 bg-amber-100/65 px-3 py-2 text-xs font-medium text-amber-900 shadow-sm backdrop-blur-sm">
                {backgroundInferenceWarning}
              </div>
            )}
            <div className="flex items-center gap-2">
              <label htmlFor="model-select" className="text-sm text-gray-600">
                Model:
              </label>
              {isLoadingModels ? (
                <div className="text-sm text-gray-500">Loading models...</div>
              ) : installedModels.length === 0 ? (
                <div className="text-sm text-red-600">No models installed</div>
              ) : (
                <select
                  id="model-select"
                  value={selectedModel}
                  onChange={(e) => setSelectedModel(e.target.value)}
                  className="px-3 py-1.5 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-desert-green focus:border-transparent bg-white"
                >
                  {installedModels.map((model) => (
                    <option key={model.name} value={model.name}>
                      {model.name} ({formatBytes(model.size)})
                    </option>
                  ))}
                </select>
              )}
              {!isLoadingModels && installedModels.length > 0 && (
                <button
                  type="button"
                  onClick={() => loadModelMutation.mutate(selectedModel)}
                  disabled={
                    !selectedModel ||
                    loadModelMutation.isPending ||
                    selectedModel === activeLoadedChatModel
                  }
                  className={classNames(
                    'rounded-lg px-3 py-1.5 text-sm font-medium transition-colors',
                    !selectedModel || loadModelMutation.isPending || selectedModel === activeLoadedChatModel
                      ? 'cursor-not-allowed bg-gray-200 text-gray-500'
                      : 'bg-desert-green text-white hover:bg-desert-green/90'
                  )}
                >
                  {loadModelMutation.isPending ? 'Loading...' : 'Load'}
                </button>
              )}
            </div>
            {(pendingLoadModel || activeLoadedChatModel || activeChatModel) && (
              <div className="rounded-lg border border-gray-200 bg-white/80 px-3 py-1.5 text-xs text-gray-600">
                {pendingLoadModel && !selectedLoadedModel ? (
                  <>
                    Loading target:{' '}
                    <span className="font-medium text-gray-800">{pendingLoadModel}</span>
                  </>
                ) : (
                  <>
                    Active:{' '}
                    <span className="font-medium text-gray-800">
                      {activeLoadedChatModel || activeChatModel}
                    </span>
                  </>
                )}
              </div>
            )}
            {isInModal && (
              <button
                onClick={() => {
                  if (onClose) {
                    onClose()
                  }
                }}
                className="rounded-lg hover:bg-gray-100 transition-colors"
              >
                <IconX className="h-6 w-6 text-gray-500" />
              </button>
            )}
          </div>
        </div>
        <ChatInterface
          messages={messages}
          onSendMessage={handleSendMessage}
          onStopGeneration={handleStopGeneration}
          isGenerating={isGenerating}
          isLoading={isGenerating || chatMutation.isPending}
          chatSuggestions={chatSuggestions}
          chatSuggestionsEnabled={suggestionsEnabled}
          chatSuggestionsLoading={chatSuggestionsLoading}
          rewriteModelAvailable={rewriteModelAvailable}
          rewriteModelName={rewriteModelName}
        />
      </div>
    </div>
  )
}
