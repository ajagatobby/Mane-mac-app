import { Injectable, Logger } from '@nestjs/common';
import {
  AgentTool,
  ToolParameter,
  ToolResult,
  FileAction,
} from './tool.interface';
import * as path from 'path';

/**
 * Generates unique action IDs
 */
function generateActionId(): string {
  return `action_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

/**
 * MoveFile Tool
 * Creates an action to move a file to a new location
 */
@Injectable()
export class MoveFileTool implements AgentTool {
  private readonly logger = new Logger(MoveFileTool.name);

  readonly name = 'moveFile';

  readonly description =
    'Move a file from one location to another. ' +
    'The destination can be a folder path (file keeps its name) or a full path with filename. ' +
    'Returns an action that will be executed after user confirmation.';

  readonly parameters: ToolParameter[] = [
    {
      name: 'sourcePath',
      type: 'string',
      description: 'The full path of the file to move',
      required: true,
    },
    {
      name: 'destinationPath',
      type: 'string',
      description:
        'The destination path (folder or full path with new filename)',
      required: true,
    },
  ];

  async execute(params: Record<string, unknown>): Promise<ToolResult> {
    const sourcePath = params.sourcePath as string;
    const destinationPath = params.destinationPath as string;

    if (!sourcePath || !destinationPath) {
      return {
        success: false,
        error: 'Both sourcePath and destinationPath are required',
      };
    }

    // Normalize paths
    const normalizedSource = path.resolve(sourcePath);
    const normalizedDest = path.resolve(destinationPath);

    // Determine if destination is a folder or full path
    const destIsFolder = !path.extname(normalizedDest);
    const finalDest = destIsFolder
      ? path.join(normalizedDest, path.basename(normalizedSource))
      : normalizedDest;

    const action: FileAction = {
      id: generateActionId(),
      type: 'move',
      sourcePath: normalizedSource,
      destinationPath: finalDest,
      requiresPermission: path.dirname(finalDest),
      description: `Move "${path.basename(normalizedSource)}" to "${finalDest}"`,
    };

    this.logger.log(`Created move action: ${action.id}`);

    return {
      success: true,
      data: { action },
    };
  }
}

/**
 * CreateFolder Tool
 * Creates an action to create a new folder
 */
@Injectable()
export class CreateFolderTool implements AgentTool {
  private readonly logger = new Logger(CreateFolderTool.name);

  readonly name = 'createFolder';

  readonly description =
    'Create a new folder at the specified path. ' +
    'Parent directories will be created if they do not exist. ' +
    'Returns an action that will be executed after user confirmation.';

  readonly parameters: ToolParameter[] = [
    {
      name: 'folderPath',
      type: 'string',
      description: 'The full path where the folder should be created',
      required: true,
    },
  ];

  async execute(params: Record<string, unknown>): Promise<ToolResult> {
    const folderPath = params.folderPath as string;

    if (!folderPath) {
      return {
        success: false,
        error: 'folderPath is required',
      };
    }

    const normalizedPath = path.resolve(folderPath);

    const action: FileAction = {
      id: generateActionId(),
      type: 'createFolder',
      destinationPath: normalizedPath,
      requiresPermission: path.dirname(normalizedPath),
      description: `Create folder "${normalizedPath}"`,
    };

    this.logger.log(`Created createFolder action: ${action.id}`);

    return {
      success: true,
      data: { action },
    };
  }
}

/**
 * RenameFile Tool
 * Creates an action to rename a file
 */
@Injectable()
export class RenameFileTool implements AgentTool {
  private readonly logger = new Logger(RenameFileTool.name);

  readonly name = 'renameFile';

  readonly description =
    'Rename a file to a new name (keeping it in the same folder). ' +
    'Returns an action that will be executed after user confirmation.';

  readonly parameters: ToolParameter[] = [
    {
      name: 'filePath',
      type: 'string',
      description: 'The full path of the file to rename',
      required: true,
    },
    {
      name: 'newName',
      type: 'string',
      description: 'The new filename (without path)',
      required: true,
    },
  ];

  async execute(params: Record<string, unknown>): Promise<ToolResult> {
    const filePath = params.filePath as string;
    const newName = params.newName as string;

    if (!filePath || !newName) {
      return {
        success: false,
        error: 'Both filePath and newName are required',
      };
    }

    const normalizedPath = path.resolve(filePath);
    const directory = path.dirname(normalizedPath);
    const newPath = path.join(directory, newName);

    const action: FileAction = {
      id: generateActionId(),
      type: 'rename',
      sourcePath: normalizedPath,
      destinationPath: newPath,
      requiresPermission: directory,
      description: `Rename "${path.basename(normalizedPath)}" to "${newName}"`,
    };

    this.logger.log(`Created rename action: ${action.id}`);

    return {
      success: true,
      data: { action },
    };
  }
}

/**
 * DeleteFile Tool
 * Creates an action to delete a file
 */
@Injectable()
export class DeleteFileTool implements AgentTool {
  private readonly logger = new Logger(DeleteFileTool.name);

  readonly name = 'deleteFile';

  readonly description =
    'Delete a file permanently. This action cannot be undone. ' +
    'Returns an action that will be executed after user confirmation.';

  readonly parameters: ToolParameter[] = [
    {
      name: 'filePath',
      type: 'string',
      description: 'The full path of the file to delete',
      required: true,
    },
  ];

  async execute(params: Record<string, unknown>): Promise<ToolResult> {
    const filePath = params.filePath as string;

    if (!filePath) {
      return {
        success: false,
        error: 'filePath is required',
      };
    }

    const normalizedPath = path.resolve(filePath);

    const action: FileAction = {
      id: generateActionId(),
      type: 'delete',
      sourcePath: normalizedPath,
      requiresPermission: path.dirname(normalizedPath),
      description: `Delete "${path.basename(normalizedPath)}"`,
    };

    this.logger.log(`Created delete action: ${action.id}`);

    return {
      success: true,
      data: { action },
    };
  }
}

/**
 * CopyFile Tool
 * Creates an action to copy a file to a new location
 */
@Injectable()
export class CopyFileTool implements AgentTool {
  private readonly logger = new Logger(CopyFileTool.name);

  readonly name = 'copyFile';

  readonly description =
    'Copy a file to a new location while keeping the original. ' +
    'The destination can be a folder path (file keeps its name) or a full path with filename. ' +
    'Returns an action that will be executed after user confirmation.';

  readonly parameters: ToolParameter[] = [
    {
      name: 'sourcePath',
      type: 'string',
      description: 'The full path of the file to copy',
      required: true,
    },
    {
      name: 'destinationPath',
      type: 'string',
      description:
        'The destination path (folder or full path with new filename)',
      required: true,
    },
  ];

  async execute(params: Record<string, unknown>): Promise<ToolResult> {
    const sourcePath = params.sourcePath as string;
    const destinationPath = params.destinationPath as string;

    if (!sourcePath || !destinationPath) {
      return {
        success: false,
        error: 'Both sourcePath and destinationPath are required',
      };
    }

    const normalizedSource = path.resolve(sourcePath);
    const normalizedDest = path.resolve(destinationPath);

    // Determine if destination is a folder or full path
    const destIsFolder = !path.extname(normalizedDest);
    const finalDest = destIsFolder
      ? path.join(normalizedDest, path.basename(normalizedSource))
      : normalizedDest;

    const action: FileAction = {
      id: generateActionId(),
      type: 'copy',
      sourcePath: normalizedSource,
      destinationPath: finalDest,
      requiresPermission: path.dirname(finalDest),
      description: `Copy "${path.basename(normalizedSource)}" to "${finalDest}"`,
    };

    this.logger.log(`Created copy action: ${action.id}`);

    return {
      success: true,
      data: { action },
    };
  }
}

/**
 * DeleteFolder Tool
 * Creates an action to delete an empty folder
 */
@Injectable()
export class DeleteFolderTool implements AgentTool {
  private readonly logger = new Logger(DeleteFolderTool.name);

  readonly name = 'deleteFolder';

  readonly description =
    'Delete an empty folder. The folder must be empty for this to succeed. ' +
    'Returns an action that will be executed after user confirmation.';

  readonly parameters: ToolParameter[] = [
    {
      name: 'folderPath',
      type: 'string',
      description: 'The full path of the folder to delete',
      required: true,
    },
  ];

  async execute(params: Record<string, unknown>): Promise<ToolResult> {
    const folderPath = params.folderPath as string;

    if (!folderPath) {
      return {
        success: false,
        error: 'folderPath is required',
      };
    }

    const normalizedPath = path.resolve(folderPath);

    const action: FileAction = {
      id: generateActionId(),
      type: 'deleteFolder',
      sourcePath: normalizedPath,
      requiresPermission: path.dirname(normalizedPath),
      description: `Delete folder "${path.basename(normalizedPath)}"`,
    };

    this.logger.log(`Created deleteFolder action: ${action.id}`);

    return {
      success: true,
      data: { action },
    };
  }
}
