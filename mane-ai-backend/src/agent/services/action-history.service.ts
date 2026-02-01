import { Injectable, Logger } from '@nestjs/common';
import { FileAction, FileActionType } from '../tools';

/**
 * Executed action with metadata for undo
 */
export interface ExecutedAction {
  /** Original action that was executed */
  action: FileAction;
  /** Timestamp when executed */
  executedAt: Date;
  /** Whether the action was successful */
  success: boolean;
  /** The reverse action to undo this operation */
  reverseAction?: FileAction;
}

/**
 * Action history entry for a session
 */
export interface ActionHistoryEntry {
  sessionId: string;
  actions: ExecutedAction[];
  createdAt: Date;
  description: string;
}

/**
 * Generates unique action IDs
 */
function generateActionId(): string {
  return `undo_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

/**
 * ActionHistoryService
 * Tracks executed actions and provides undo capabilities
 */
@Injectable()
export class ActionHistoryService {
  private readonly logger = new Logger(ActionHistoryService.name);
  
  // Store action history by session ID
  private historyMap: Map<string, ActionHistoryEntry> = new Map();
  
  // Stack of session IDs for undo (most recent first)
  private undoStack: string[] = [];
  
  // Maximum history entries to keep
  private readonly maxHistoryEntries = 50;

  /**
   * Record executed actions for potential undo
   */
  recordActions(
    sessionId: string,
    actions: FileAction[],
    results: Array<{ actionId: string; success: boolean }>,
    description: string,
  ): void {
    const executedActions: ExecutedAction[] = actions.map((action) => {
      const result = results.find((r) => r.actionId === action.id);
      const success = result?.success ?? false;

      return {
        action,
        executedAt: new Date(),
        success,
        reverseAction: success ? this.createReverseAction(action) : undefined,
      };
    });

    const entry: ActionHistoryEntry = {
      sessionId,
      actions: executedActions,
      createdAt: new Date(),
      description,
    };

    this.historyMap.set(sessionId, entry);
    this.undoStack.unshift(sessionId);

    // Cleanup old entries
    this.cleanupOldEntries();

    this.logger.log(`Recorded ${executedActions.length} actions for session ${sessionId}`);
  }

  /**
   * Compute the actual file path after a move/copy operation
   * If destination is a folder, append the filename from source
   */
  private computeActualPath(sourcePath: string, destinationPath: string): string {
    const sourceFileName = sourcePath.split('/').pop() || '';
    const destFileName = destinationPath.split('/').pop() || '';
    
    // Check if destination looks like a folder (no extension or matches source filename)
    const sourceHasExt = sourceFileName.includes('.');
    const destHasExt = destFileName.includes('.');
    
    // If source has extension but dest doesn't, dest is likely a folder
    if (sourceHasExt && !destHasExt) {
      return `${destinationPath}/${sourceFileName}`;
    }
    
    // If dest already includes the filename, return as-is
    return destinationPath;
  }

  /**
   * Create the reverse action for undoing an operation
   */
  private createReverseAction(action: FileAction): FileAction | undefined {
    switch (action.type) {
      case 'move':
        // Reverse move: move back from destination to source
        if (action.sourcePath && action.destinationPath) {
          // Compute where the file actually ended up after the move
          const actualNewLocation = this.computeActualPath(action.sourcePath, action.destinationPath);
          // Original location is the source directory with original filename
          const originalLocation = action.sourcePath;
          
          this.logger.debug(`Creating reverse move: ${actualNewLocation} -> ${originalLocation}`);
          
          return {
            id: generateActionId(),
            type: 'move',
            sourcePath: actualNewLocation,
            destinationPath: originalLocation,
            requiresPermission: originalLocation.substring(0, originalLocation.lastIndexOf('/')),
            description: `Undo: Move "${actualNewLocation.split('/').pop()}" back to ${originalLocation.substring(0, originalLocation.lastIndexOf('/'))}`,
          };
        }
        break;

      case 'copy':
        // Reverse copy: delete the copied file
        if (action.sourcePath && action.destinationPath) {
          // Compute where the copy actually ended up
          const actualCopyLocation = this.computeActualPath(action.sourcePath, action.destinationPath);
          
          return {
            id: generateActionId(),
            type: 'delete',
            sourcePath: actualCopyLocation,
            requiresPermission: actualCopyLocation.substring(0, actualCopyLocation.lastIndexOf('/')),
            description: `Undo: Delete copied file "${actualCopyLocation.split('/').pop()}"`,
          };
        }
        break;

      case 'rename':
        // Reverse rename: rename back to original name
        if (action.sourcePath && action.destinationPath) {
          // After rename, file is at destinationPath
          // Reverse: rename from destinationPath back to sourcePath
          return {
            id: generateActionId(),
            type: 'rename',
            sourcePath: action.destinationPath,
            destinationPath: action.sourcePath,
            requiresPermission: action.destinationPath.substring(0, action.destinationPath.lastIndexOf('/')),
            description: `Undo: Rename back to "${action.sourcePath.split('/').pop()}"`,
          };
        }
        break;

      case 'createFolder':
        // Reverse createFolder: delete the folder (only if empty)
        if (action.destinationPath) {
          return {
            id: generateActionId(),
            type: 'deleteFolder' as FileActionType,
            sourcePath: action.destinationPath,
            requiresPermission: action.destinationPath.substring(0, action.destinationPath.lastIndexOf('/')),
            description: `Undo: Remove folder "${action.destinationPath.split('/').pop()}"`,
          };
        }
        break;

      case 'delete':
        // Cannot undo delete unless we have a backup mechanism
        this.logger.warn('Delete actions cannot be undone without a backup system');
        return undefined;

      default:
        return undefined;
    }

    return undefined;
  }

  /**
   * Get the most recent undoable session
   */
  getLastUndoableSession(): ActionHistoryEntry | undefined {
    for (const sessionId of this.undoStack) {
      const entry = this.historyMap.get(sessionId);
      if (entry && entry.actions.some((a) => a.success && a.reverseAction)) {
        return entry;
      }
    }
    return undefined;
  }

  /**
   * Get undo actions for the most recent session
   */
  getUndoActions(): FileAction[] {
    const lastSession = this.getLastUndoableSession();
    if (!lastSession) {
      return [];
    }

    // Get reverse actions in reverse order (undo most recent first)
    const reverseActions = lastSession.actions
      .filter((a) => a.success && a.reverseAction)
      .map((a) => a.reverseAction!)
      .reverse();

    return reverseActions;
  }

  /**
   * Get undo actions for a specific session
   */
  getUndoActionsForSession(sessionId: string): FileAction[] {
    const entry = this.historyMap.get(sessionId);
    if (!entry) {
      return [];
    }

    return entry.actions
      .filter((a) => a.success && a.reverseAction)
      .map((a) => a.reverseAction!)
      .reverse();
  }

  /**
   * Mark a session as undone (remove from undo stack)
   */
  markAsUndone(sessionId: string): void {
    const index = this.undoStack.indexOf(sessionId);
    if (index !== -1) {
      this.undoStack.splice(index, 1);
    }
    this.historyMap.delete(sessionId);
    this.logger.log(`Marked session ${sessionId} as undone`);
  }

  /**
   * Get action history summary
   */
  getHistorySummary(): Array<{
    sessionId: string;
    description: string;
    actionCount: number;
    successCount: number;
    createdAt: Date;
    canUndo: boolean;
  }> {
    return Array.from(this.historyMap.values()).map((entry) => ({
      sessionId: entry.sessionId,
      description: entry.description,
      actionCount: entry.actions.length,
      successCount: entry.actions.filter((a) => a.success).length,
      createdAt: entry.createdAt,
      canUndo: entry.actions.some((a) => a.success && a.reverseAction),
    }));
  }

  /**
   * Clean up old history entries
   */
  private cleanupOldEntries(): void {
    while (this.undoStack.length > this.maxHistoryEntries) {
      const oldestSessionId = this.undoStack.pop();
      if (oldestSessionId) {
        this.historyMap.delete(oldestSessionId);
      }
    }
  }

  /**
   * Clear all history
   */
  clearHistory(): void {
    this.historyMap.clear();
    this.undoStack = [];
    this.logger.log('Cleared all action history');
  }
}
