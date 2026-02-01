import {
  Controller,
  Post,
  Get,
  Body,
  Res,
  Query,
  HttpStatus,
  HttpException,
} from '@nestjs/common';
import { Response } from 'express';
import { AgentService } from './agent.service';
import { DedupService } from './services/dedup.service';
import { ClusterService } from './services/cluster.service';
import { ActionHistoryService } from './services/action-history.service';
import {
  ExecuteAgentDto,
  ConfirmActionsDto,
  ActionResultsDto,
  OrganizeDto,
  FindDuplicatesDto,
} from './dto';

@Controller('agent')
export class AgentController {
  constructor(
    private readonly agentService: AgentService,
    private readonly dedupService: DedupService,
    private readonly clusterService: ClusterService,
    private readonly actionHistoryService: ActionHistoryService,
  ) {}

  /**
   * Execute an agent command
   * Supports both streaming and non-streaming modes
   */
  @Post('execute')
  async execute(
    @Body() dto: ExecuteAgentDto,
    @Res() res: Response,
  ): Promise<void> {
    if (dto.stream) {
      // Streaming mode - SSE
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');

      try {
        for await (const step of this.agentService.executeStream(dto.command)) {
          const data = JSON.stringify(step);
          res.write(`data: ${data}\n\n`);
        }
        res.write('data: [DONE]\n\n');
        res.end();
      } catch (error: any) {
        const errorData = JSON.stringify({
          type: 'error',
          content: error.message,
        });
        res.write(`data: ${errorData}\n\n`);
        res.end();
      }
    } else {
      // Non-streaming mode - JSON response
      try {
        const result = await this.agentService.execute(dto.command);
        res.status(HttpStatus.OK).json(result);
      } catch (error: any) {
        res.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
          thought: '',
          actions: [],
          finalAnswer: `Error: ${error.message}`,
          requiresConfirmation: false,
          error: error.message,
        });
      }
    }
  }

  /**
   * Confirm pending actions for execution
   * Returns the actions to be executed by the Swift frontend
   */
  @Post('confirm')
  async confirmActions(@Body() dto: ConfirmActionsDto) {
    const actions = this.agentService.confirmActions(dto.sessionId);

    if (!actions) {
      throw new HttpException(
        'Session not found or expired',
        HttpStatus.NOT_FOUND,
      );
    }

    return {
      success: true,
      actions,
      message: `${actions.length} actions ready for execution`,
    };
  }

  /**
   * Cancel pending actions
   */
  @Post('cancel')
  async cancelActions(@Body() dto: ConfirmActionsDto) {
    const cancelled = this.agentService.cancelActions(dto.sessionId);

    return {
      success: cancelled,
      message: cancelled ? 'Actions cancelled' : 'Session not found',
    };
  }

  /**
   * Report action execution results from Swift
   * Records successful actions for potential undo
   */
  @Post('results')
  async reportResults(@Body() dto: ActionResultsDto) {
    const successCount = dto.results.filter((r) => r.success).length;
    const failCount = dto.results.length - successCount;

    // Get the original actions from the pending session
    const pendingActions = this.agentService.getPendingActions(dto.sessionId);
    
    // Record actions for undo if we have the original actions
    if (pendingActions && pendingActions.actions.length > 0) {
      this.actionHistoryService.recordActions(
        dto.sessionId,
        pendingActions.actions,
        dto.results,
        `Executed ${successCount} actions`,
      );
    }

    return {
      success: true,
      summary: {
        total: dto.results.length,
        succeeded: successCount,
        failed: failCount,
      },
      results: dto.results,
      canUndo: successCount > 0,
    };
  }

  /**
   * Get pending actions for a session
   */
  @Get('pending')
  async getPendingActions(@Query('sessionId') sessionId: string) {
    if (!sessionId) {
      throw new HttpException(
        'sessionId is required',
        HttpStatus.BAD_REQUEST,
      );
    }

    const pending = this.agentService.getPendingActions(sessionId);

    if (!pending) {
      throw new HttpException(
        'Session not found or expired',
        HttpStatus.NOT_FOUND,
      );
    }

    return {
      success: true,
      ...pending,
    };
  }

  /**
   * Find duplicate files
   */
  @Post('duplicates')
  async findDuplicates(@Body() dto: FindDuplicatesDto) {
    try {
      const duplicates = await this.dedupService.findDuplicates(
        dto.mediaType || 'all',
        dto.threshold || 0.95,
      );

      return {
        success: true,
        totalGroups: duplicates.length,
        duplicates,
      };
    } catch (error: any) {
      throw new HttpException(
        `Failed to find duplicates: ${error.message}`,
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  /**
   * Auto-organize files using clustering
   */
  @Post('organize')
  async organizeFiles(@Body() dto: OrganizeDto) {
    try {
      const clusters = await this.clusterService.organizeFiles();

      if (dto.preview) {
        // Preview mode - just return the clusters
        return {
          success: true,
          preview: true,
          clusters,
        };
      }

      // Generate actions for organizing
      const actions = await this.clusterService.generateOrganizeActions(
        clusters,
        dto.targetFolder,
      );

      // Store as pending actions
      if (actions.length > 0) {
        const sessionId = `organize_${Date.now()}`;
        // Actions will be returned directly since organize is a special case
        return {
          success: true,
          preview: false,
          clusters,
          actions,
          message: `Generated ${actions.length} organization actions`,
        };
      }

      return {
        success: true,
        preview: false,
        clusters,
        actions: [],
        message: 'No organization actions needed',
      };
    } catch (error: any) {
      throw new HttpException(
        `Failed to organize files: ${error.message}`,
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  /**
   * Get undo actions for the most recent operation
   */
  @Get('undo')
  async getUndoActions() {
    const lastSession = this.actionHistoryService.getLastUndoableSession();
    
    if (!lastSession) {
      return {
        success: false,
        canUndo: false,
        message: 'No actions to undo',
        actions: [],
      };
    }

    const undoActions = this.actionHistoryService.getUndoActions();

    return {
      success: true,
      canUndo: undoActions.length > 0,
      sessionId: lastSession.sessionId,
      description: lastSession.description,
      actionCount: undoActions.length,
      actions: undoActions,
      message: `Can undo ${undoActions.length} action(s)`,
    };
  }

  /**
   * Execute undo for the most recent operation
   * Returns the undo actions for the Swift frontend to execute
   */
  @Post('undo')
  async executeUndo(@Body() body: { sessionId?: string }) {
    let undoActions;
    let sessionId;

    if (body.sessionId) {
      // Undo specific session
      undoActions = this.actionHistoryService.getUndoActionsForSession(body.sessionId);
      sessionId = body.sessionId;
    } else {
      // Undo most recent
      const lastSession = this.actionHistoryService.getLastUndoableSession();
      if (!lastSession) {
        throw new HttpException('No actions to undo', HttpStatus.NOT_FOUND);
      }
      undoActions = this.actionHistoryService.getUndoActions();
      sessionId = lastSession.sessionId;
    }

    if (undoActions.length === 0) {
      throw new HttpException('No undoable actions found', HttpStatus.NOT_FOUND);
    }

    // Mark as undone (remove from history)
    this.actionHistoryService.markAsUndone(sessionId);

    return {
      success: true,
      sessionId,
      actions: undoActions,
      message: `Undo ${undoActions.length} action(s)`,
    };
  }

  /**
   * Get action history
   */
  @Get('history')
  async getHistory() {
    const history = this.actionHistoryService.getHistorySummary();

    return {
      success: true,
      entries: history,
      undoableCount: history.filter((h) => h.canUndo).length,
    };
  }

  /**
   * Clear action history
   */
  @Post('history/clear')
  async clearHistory() {
    this.actionHistoryService.clearHistory();

    return {
      success: true,
      message: 'Action history cleared',
    };
  }

  /**
   * Get agent status
   */
  @Get('status')
  async getStatus() {
    const lastUndoable = this.actionHistoryService.getLastUndoableSession();

    return {
      ...this.agentService.getStatus(),
      features: {
        duplicateDetection: true,
        autoOrganization: true,
        undo: true,
      },
      canUndo: !!lastUndoable,
      lastUndoDescription: lastUndoable?.description,
    };
  }
}
