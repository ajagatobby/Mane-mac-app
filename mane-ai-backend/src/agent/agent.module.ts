import { Module } from '@nestjs/common';
import { AgentService } from './agent.service';
import { AgentController } from './agent.controller';
import { LanceDBModule } from '../lancedb';
import { ConfigModule } from '../config';
import {
  ToolRegistry,
  FindFilesTool,
  MoveFileTool,
  CreateFolderTool,
  RenameFileTool,
  DeleteFileTool,
  DeleteFolderTool,
  CopyFileTool,
} from './tools';
import { DedupService } from './services/dedup.service';
import { ClusterService } from './services/cluster.service';
import { ActionHistoryService } from './services/action-history.service';

@Module({
  imports: [ConfigModule, LanceDBModule],
  controllers: [AgentController],
  providers: [
    AgentService,
    ToolRegistry,
    FindFilesTool,
    MoveFileTool,
    CreateFolderTool,
    RenameFileTool,
    DeleteFileTool,
    DeleteFolderTool,
    CopyFileTool,
    DedupService,
    ClusterService,
    ActionHistoryService,
  ],
  exports: [AgentService, DedupService, ClusterService, ActionHistoryService],
})
export class AgentModule {}
