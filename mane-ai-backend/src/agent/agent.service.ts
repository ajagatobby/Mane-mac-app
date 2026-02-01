import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '../config';
import { LanceDBService } from '../lancedb';
import { ChatOllama } from '@langchain/ollama';
import { HumanMessage, SystemMessage, AIMessage } from '@langchain/core/messages';
import {
  ToolRegistry,
  FindFilesTool,
  MoveFileTool,
  CreateFolderTool,
  RenameFileTool,
  DeleteFileTool,
  CopyFileTool,
  FileAction,
  AgentResponse,
  PendingActions,
} from './tools';

/**
 * ReAct Agent Prompt Template
 * Implements Reasoning + Acting pattern for file organization tasks
 */
const REACT_SYSTEM_PROMPT = `You are an intelligent file organization assistant. You can search, move, rename, and organize files.

AVAILABLE TOOLS:
{tools}

RESPONSE FORMAT - You must respond in ONE of these two formats:

FORMAT 1 - When you need to use a tool:
Thought: [your reasoning - one sentence]
Action: [exact tool name]
Action Input: [valid JSON object]

FORMAT 2 - When you are done and have a final answer:
Thought: [your final reasoning]
Final Answer: [your complete response to the user]

CRITICAL RULES:
1. Output ONLY ONE action per response. STOP after Action Input and wait for the Observation.
2. DO NOT continue after Action Input. DO NOT assume results. DO NOT write multiple actions.
3. DO NOT write placeholder text like "[receives results]" or "[continues...]".
4. After you see "Observation:", analyze the ACTUAL results before your next action.
5. Use EXACT file paths from findFiles results - never make up paths.
6. Always call findFiles FIRST before any move/delete operations.
7. Call createFolder BEFORE moving files into a new folder.
8. Only output "Final Answer:" when you have completed ALL necessary tool calls.

WORKFLOW EXAMPLE:
User: "Move cat images to Desktop/cats"

Response 1:
Thought: I need to find images of cats first.
Action: findFiles
Action Input: {"query": "cat images", "mediaType": "image", "limit": 20}

[System provides Observation with actual results]

Response 2:
Thought: Found 2 cat images. Now I need to create the cats folder.
Action: createFolder
Action Input: {"folderPath": "/Users/name/Desktop/cats"}

[System provides Observation]

Response 3:
Thought: Folder action created. Now I'll move the first image.
Action: moveFile
Action Input: {"sourcePath": "/actual/path/from/results/cat1.jpg", "destinationPath": "/Users/name/Desktop/cats"}

[Continue one action at a time until done, then give Final Answer]`;

interface ParsedAction {
  tool: string;
  input: Record<string, unknown>;
}

interface ReActStep {
  thought: string;
  action?: ParsedAction;
  observation?: string;
}

@Injectable()
export class AgentService implements OnModuleInit {
  private readonly logger = new Logger(AgentService.name);
  private chatModel: ChatOllama | null = null;
  private isAvailable = false;
  private pendingActionsMap: Map<string, PendingActions> = new Map();

  constructor(
    private readonly configService: ConfigService,
    private readonly lanceDBService: LanceDBService,
    private readonly toolRegistry: ToolRegistry,
    private readonly findFilesTool: FindFilesTool,
    private readonly moveFileTool: MoveFileTool,
    private readonly createFolderTool: CreateFolderTool,
    private readonly renameFileTool: RenameFileTool,
    private readonly deleteFileTool: DeleteFileTool,
    private readonly copyFileTool: CopyFileTool,
  ) {}

  async onModuleInit() {
    await this.initialize();
  }

  private async initialize(): Promise<void> {
    // Register all tools
    this.toolRegistry.registerTool(this.findFilesTool);
    this.toolRegistry.registerTool(this.moveFileTool);
    this.toolRegistry.registerTool(this.createFolderTool);
    this.toolRegistry.registerTool(this.renameFileTool);
    this.toolRegistry.registerTool(this.deleteFileTool);
    this.toolRegistry.registerTool(this.copyFileTool);

    // Initialize the chat model
    const ollamaUrl = this.configService.getOllamaUrl();
    const ollamaModel = this.configService.getOllamaModel();

    this.chatModel = new ChatOllama({
      baseUrl: ollamaUrl,
      model: ollamaModel,
      temperature: 0.3, // Lower temperature for more consistent tool use
    });

    await this.checkHealth();
    this.logger.log('Agent service initialized with tools: ' + this.toolRegistry.getToolNames().join(', '));
  }

  async checkHealth(): Promise<boolean> {
    try {
      const ollamaUrl = this.configService.getOllamaUrl();
      const response = await fetch(`${ollamaUrl}/api/tags`);
      this.isAvailable = response.ok;
      return this.isAvailable;
    } catch {
      this.isAvailable = false;
      return false;
    }
  }

  /**
   * Execute an agent command using the ReAct loop
   */
  async execute(command: string): Promise<AgentResponse> {
    if (!this.chatModel) {
      return {
        thought: '',
        actions: [],
        finalAnswer: 'Agent not initialized',
        requiresConfirmation: false,
        error: 'Agent not initialized',
      };
    }

    if (!this.isAvailable) {
      await this.checkHealth();
      if (!this.isAvailable) {
        return {
          thought: '',
          actions: [],
          finalAnswer: 'Ollama is not available. Please ensure Ollama is running.',
          requiresConfirmation: false,
          error: 'Ollama unavailable',
        };
      }
    }

    try {
      const result = await this.runReActLoop(command);
      return result;
    } catch (error: any) {
      this.logger.error(`Agent execution failed: ${error.message}`);
      return {
        thought: '',
        actions: [],
        finalAnswer: `Error: ${error.message}`,
        requiresConfirmation: false,
        error: error.message,
      };
    }
  }

  /**
   * Main ReAct loop implementation
   */
  private async runReActLoop(command: string): Promise<AgentResponse> {
    const toolDescriptions = this.toolRegistry.generateToolDescriptions();
    const systemPrompt = REACT_SYSTEM_PROMPT.replace('{tools}', toolDescriptions);

    const messages: (SystemMessage | HumanMessage | AIMessage)[] = [
      new SystemMessage(systemPrompt),
      new HumanMessage(command),
    ];

    const steps: ReActStep[] = [];
    const collectedActions: FileAction[] = [];
    const maxIterations = 15;
    let iteration = 0;
    let finalAnswer = '';
    let lastThought = '';

    while (iteration < maxIterations) {
      iteration++;
      this.logger.log(`ReAct iteration ${iteration}`);

      // Get LLM response
      const response = await this.chatModel!.invoke(messages);
      const content = typeof response.content === 'string'
        ? response.content
        : JSON.stringify(response.content);

      this.logger.debug(`LLM Response:\n${content}`);

      // Parse the response
      const parsed = this.parseReActResponse(content);

      if (parsed.thought) {
        lastThought = parsed.thought;
      }

      // Check for final answer
      if (parsed.finalAnswer) {
        finalAnswer = parsed.finalAnswer;
        this.logger.log('Agent reached final answer');
        break;
      }

      // Execute action if present
      if (parsed.action) {
        const step: ReActStep = {
          thought: parsed.thought || '',
          action: parsed.action,
        };

        // Execute the tool
        const toolResult = await this.toolRegistry.executeTool(
          parsed.action.tool,
          parsed.action.input,
        );

        // Collect file actions
        if (toolResult.success && toolResult.data) {
          const data = toolResult.data as Record<string, unknown>;
          if (data.action) {
            collectedActions.push(data.action as FileAction);
          }
        }

        // Format observation
        const observation = toolResult.success
          ? JSON.stringify(toolResult.data, null, 2)
          : `Error: ${toolResult.error}`;

        step.observation = observation;
        steps.push(step);

        // Add to conversation
        messages.push(new AIMessage(content));
        messages.push(new HumanMessage(`Observation: ${observation}`));
      } else if (!parsed.finalAnswer) {
        // No action and no final answer - nudge the model
        messages.push(new AIMessage(content));
        messages.push(
          new HumanMessage(
            'Please continue with your next Action or provide a Final Answer.',
          ),
        );
      }
    }

    if (!finalAnswer && iteration >= maxIterations) {
      finalAnswer = 'I was unable to complete the task within the allowed steps. Please try a simpler command.';
    }

    // Determine if confirmation is needed
    const requiresConfirmation = collectedActions.length > 0;

    // Store pending actions if confirmation required
    let sessionId: string | undefined;
    if (requiresConfirmation) {
      sessionId = this.storePendingActions(collectedActions);
    }

    return {
      thought: lastThought,
      actions: collectedActions,
      finalAnswer: sessionId
        ? `${finalAnswer}\n\n[Session: ${sessionId}]`
        : finalAnswer,
      requiresConfirmation,
    };
  }

  /**
   * Parse ReAct-style response from LLM
   * Priority: Action > Final Answer (if model outputs both, take Action)
   */
  private parseReActResponse(content: string): {
    thought?: string;
    action?: ParsedAction;
    finalAnswer?: string;
  } {
    const result: {
      thought?: string;
      action?: ParsedAction;
      finalAnswer?: string;
    } = {};

    // Extract Thought (first occurrence, stop at Action or Final Answer)
    const thoughtMatch = content.match(/Thought:\s*(.+?)(?=\nAction:|\nFinal Answer:|$)/s);
    if (thoughtMatch) {
      result.thought = thoughtMatch[1].trim();
    }

    // First, check for Action - this takes priority
    // Look for the FIRST Action/Action Input pair only
    const actionMatch = content.match(/Action:\s*(\w+)/);
    const inputMatch = content.match(/Action Input:\s*(\{[^}]*\})/);

    if (actionMatch && inputMatch) {
      try {
        const input = JSON.parse(inputMatch[1]);
        result.action = {
          tool: actionMatch[1],
          input,
        };
        // If we found an action, return immediately - don't look for Final Answer
        // The model should not output both in the same response
        return result;
      } catch (e) {
        this.logger.warn(`Failed to parse action input: ${inputMatch[1]}`);
      }
    }

    // Only check for Final Answer if no valid action was found
    const finalMatch = content.match(/Final Answer:\s*(.+)$/s);
    if (finalMatch) {
      result.finalAnswer = finalMatch[1].trim();
    }

    return result;
  }

  /**
   * Store pending actions for later confirmation
   */
  private storePendingActions(actions: FileAction[]): string {
    const sessionId = `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

    this.pendingActionsMap.set(sessionId, {
      sessionId,
      actions,
      createdAt: new Date(),
      expiresAt,
    });

    // Clean up expired sessions
    this.cleanupExpiredSessions();

    this.logger.log(`Stored ${actions.length} pending actions in session ${sessionId}`);
    return sessionId;
  }

  /**
   * Get pending actions for a session
   */
  getPendingActions(sessionId: string): PendingActions | undefined {
    const pending = this.pendingActionsMap.get(sessionId);
    if (pending && pending.expiresAt > new Date()) {
      return pending;
    }
    return undefined;
  }

  /**
   * Confirm and return actions for execution
   */
  confirmActions(sessionId: string): FileAction[] | undefined {
    const pending = this.pendingActionsMap.get(sessionId);
    if (pending && pending.expiresAt > new Date()) {
      this.pendingActionsMap.delete(sessionId);
      return pending.actions;
    }
    return undefined;
  }

  /**
   * Cancel pending actions
   */
  cancelActions(sessionId: string): boolean {
    return this.pendingActionsMap.delete(sessionId);
  }

  /**
   * Clean up expired sessions
   */
  private cleanupExpiredSessions(): void {
    const now = new Date();
    for (const [sessionId, pending] of this.pendingActionsMap) {
      if (pending.expiresAt <= now) {
        this.pendingActionsMap.delete(sessionId);
        this.logger.log(`Cleaned up expired session: ${sessionId}`);
      }
    }
  }

  /**
   * Execute streaming agent command (yields intermediate steps)
   */
  async *executeStream(command: string): AsyncGenerator<{
    type: 'thought' | 'action' | 'observation' | 'final';
    content: string;
    action?: FileAction;
  }> {
    if (!this.chatModel || !this.isAvailable) {
      yield {
        type: 'final',
        content: 'Agent not available. Please ensure Ollama is running.',
      };
      return;
    }

    const toolDescriptions = this.toolRegistry.generateToolDescriptions();
    const systemPrompt = REACT_SYSTEM_PROMPT.replace('{tools}', toolDescriptions);

    const messages: (SystemMessage | HumanMessage | AIMessage)[] = [
      new SystemMessage(systemPrompt),
      new HumanMessage(command),
    ];

    const collectedActions: FileAction[] = [];
    const maxIterations = 15;
    let iteration = 0;

    while (iteration < maxIterations) {
      iteration++;

      const response = await this.chatModel.invoke(messages);
      const content = typeof response.content === 'string'
        ? response.content
        : JSON.stringify(response.content);

      const parsed = this.parseReActResponse(content);

      if (parsed.thought) {
        yield { type: 'thought', content: parsed.thought };
      }

      if (parsed.finalAnswer) {
        // Store pending actions if any
        let sessionInfo = '';
        if (collectedActions.length > 0) {
          const sessionId = this.storePendingActions(collectedActions);
          sessionInfo = `\n\n[Session: ${sessionId}]`;
        }
        yield { type: 'final', content: parsed.finalAnswer + sessionInfo };
        return;
      }

      if (parsed.action) {
        yield {
          type: 'action',
          content: `Using ${parsed.action.tool}...`,
        };

        const toolResult = await this.toolRegistry.executeTool(
          parsed.action.tool,
          parsed.action.input,
        );

        if (toolResult.success && toolResult.data) {
          const data = toolResult.data as Record<string, unknown>;
          if (data.action) {
            const action = data.action as FileAction;
            collectedActions.push(action);
            yield { type: 'action', content: action.description, action };
          }
        }

        const observation = toolResult.success
          ? JSON.stringify(toolResult.data, null, 2)
          : `Error: ${toolResult.error}`;

        yield { type: 'observation', content: observation };

        messages.push(new AIMessage(content));
        messages.push(new HumanMessage(`Observation: ${observation}`));
      } else {
        messages.push(new AIMessage(content));
        messages.push(
          new HumanMessage('Please continue with your next Action or provide a Final Answer.'),
        );
      }
    }

    yield {
      type: 'final',
      content: 'Maximum iterations reached. Please try a simpler command.',
    };
  }

  getStatus(): { available: boolean; tools: string[] } {
    return {
      available: this.isAvailable,
      tools: this.toolRegistry.getToolNames(),
    };
  }
}
