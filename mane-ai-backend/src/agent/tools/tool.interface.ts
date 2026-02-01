/**
 * Agent Tool Interface
 * Defines the contract for all tools available to the ReAct agent
 */

export interface ToolParameter {
  name: string;
  type: 'string' | 'number' | 'boolean' | 'array';
  description: string;
  required: boolean;
}

export interface ToolResult {
  success: boolean;
  data?: unknown;
  error?: string;
}

export interface AgentTool {
  /** Unique name for the tool */
  name: string;

  /** Description of what the tool does (shown to the LLM) */
  description: string;

  /** Parameter definitions for the tool */
  parameters: ToolParameter[];

  /** Execute the tool with given parameters */
  execute(params: Record<string, unknown>): Promise<ToolResult>;
}

/**
 * File Action Types
 * Actions that will be sent to Swift for execution
 */
export type FileActionType =
  | 'move'
  | 'copy'
  | 'rename'
  | 'delete'
  | 'createFolder'
  | 'deleteFolder';

export interface FileAction {
  /** Unique ID for tracking */
  id: string;

  /** Type of file operation */
  type: FileActionType;

  /** Source file/folder path */
  sourcePath?: string;

  /** Destination path (for move, copy, rename) */
  destinationPath?: string;

  /** Folder that needs permission access */
  requiresPermission?: string;

  /** Human-readable description of the action */
  description: string;
}

/**
 * Agent Response
 * The structured response from the agent after processing a command
 */
export interface AgentResponse {
  /** The agent's reasoning/thought process */
  thought: string;

  /** List of file actions to execute */
  actions: FileAction[];

  /** Final answer to show the user */
  finalAnswer: string;

  /** Whether user confirmation is required before execution */
  requiresConfirmation: boolean;

  /** Any errors that occurred */
  error?: string;
}

/**
 * Action Execution Result
 */
export interface ActionExecutionResult {
  actionId: string;
  success: boolean;
  error?: string;
}

/**
 * Pending Actions State
 * Used to track actions awaiting user confirmation
 */
export interface PendingActions {
  sessionId: string;
  actions: FileAction[];
  createdAt: Date;
  expiresAt: Date;
}
