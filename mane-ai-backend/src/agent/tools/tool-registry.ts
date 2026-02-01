import { Injectable, Logger } from '@nestjs/common';
import { AgentTool, ToolResult } from './tool.interface';

/**
 * Tool Registry
 * Manages all available tools for the agent
 */
@Injectable()
export class ToolRegistry {
  private readonly logger = new Logger(ToolRegistry.name);
  private tools: Map<string, AgentTool> = new Map();

  /**
   * Register a tool with the registry
   */
  registerTool(tool: AgentTool): void {
    if (this.tools.has(tool.name)) {
      this.logger.warn(`Tool "${tool.name}" is being overwritten`);
    }
    this.tools.set(tool.name, tool);
    this.logger.log(`Registered tool: ${tool.name}`);
  }

  /**
   * Get a tool by name
   */
  getTool(name: string): AgentTool | undefined {
    return this.tools.get(name);
  }

  /**
   * Get all registered tools
   */
  getAllTools(): AgentTool[] {
    return Array.from(this.tools.values());
  }

  /**
   * Get tool names
   */
  getToolNames(): string[] {
    return Array.from(this.tools.keys());
  }

  /**
   * Execute a tool by name
   */
  async executeTool(
    name: string,
    params: Record<string, unknown>,
  ): Promise<ToolResult> {
    const tool = this.tools.get(name);
    if (!tool) {
      return {
        success: false,
        error: `Tool "${name}" not found. Available tools: ${this.getToolNames().join(', ')}`,
      };
    }

    try {
      this.logger.log(`Executing tool: ${name} with params: ${JSON.stringify(params)}`);
      const result = await tool.execute(params);
      this.logger.log(`Tool ${name} completed: ${result.success}`);
      return result;
    } catch (error: any) {
      this.logger.error(`Tool ${name} failed: ${error.message}`);
      return {
        success: false,
        error: error.message,
      };
    }
  }

  /**
   * Generate tool descriptions for the LLM prompt
   */
  generateToolDescriptions(): string {
    const tools = this.getAllTools();
    if (tools.length === 0) {
      return 'No tools available.';
    }

    return tools
      .map((tool) => {
        const paramDesc = tool.parameters
          .map((p) => {
            const req = p.required ? '(required)' : '(optional)';
            return `    - ${p.name}: ${p.type} ${req} - ${p.description}`;
          })
          .join('\n');

        return `${tool.name}: ${tool.description}\n  Parameters:\n${paramDesc}`;
      })
      .join('\n\n');
  }

  /**
   * Generate JSON schema for tools (for structured output)
   */
  generateToolSchemas(): Record<string, unknown>[] {
    return this.getAllTools().map((tool) => ({
      name: tool.name,
      description: tool.description,
      parameters: {
        type: 'object',
        properties: tool.parameters.reduce(
          (acc, param) => {
            acc[param.name] = {
              type: param.type === 'array' ? 'array' : param.type,
              description: param.description,
            };
            return acc;
          },
          {} as Record<string, unknown>,
        ),
        required: tool.parameters
          .filter((p) => p.required)
          .map((p) => p.name),
      },
    }));
  }
}
