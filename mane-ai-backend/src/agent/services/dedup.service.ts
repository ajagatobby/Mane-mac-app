import { Injectable, Logger } from '@nestjs/common';
import { LanceDBService, SearchResult } from '../../lancedb';

/**
 * Duplicate Group
 * A group of files that are considered duplicates of each other
 */
export interface DuplicateGroup {
  /** Representative file (typically the oldest or first found) */
  primary: {
    filePath: string;
    fileName: string;
    mediaType: string;
  };
  /** Other files that are duplicates of the primary */
  duplicates: Array<{
    filePath: string;
    fileName: string;
    mediaType: string;
    similarity: number;
  }>;
  /** Average similarity within the group */
  averageSimilarity: number;
}

@Injectable()
export class DedupService {
  private readonly logger = new Logger(DedupService.name);

  constructor(private readonly lanceDBService: LanceDBService) {}

  /**
   * Find duplicate files based on embedding similarity
   * @param mediaType Filter by media type ('text', 'image', 'audio', 'all')
   * @param threshold Similarity threshold (0-1, default 0.95)
   */
  async findDuplicates(
    mediaType: 'text' | 'image' | 'audio' | 'all' = 'all',
    threshold: number = 0.95,
  ): Promise<DuplicateGroup[]> {
    this.logger.log(`Finding duplicates (type: ${mediaType}, threshold: ${threshold})`);

    // Get all documents
    const allDocs = await this.lanceDBService.getAllDocuments();

    // Filter by media type if specified
    const docs = mediaType === 'all'
      ? allDocs
      : allDocs.filter((d) => d.mediaType === mediaType);

    if (docs.length < 2) {
      this.logger.log('Not enough documents to find duplicates');
      return [];
    }

    // Get vectors for all documents
    const docsWithVectors = await this.getDocumentsWithVectors(docs);

    // Find duplicate groups using Union-Find
    const duplicateGroups = this.findDuplicateGroups(docsWithVectors, threshold);

    this.logger.log(`Found ${duplicateGroups.length} duplicate groups`);
    return duplicateGroups;
  }

  /**
   * Get documents with their vectors
   */
  private async getDocumentsWithVectors(
    docs: SearchResult[],
  ): Promise<Array<SearchResult & { vector: number[] }>> {
    // For now, we'll re-embed the content to get vectors
    // In a production system, you'd store vectors with documents
    const results: Array<SearchResult & { vector: number[] }> = [];

    for (const doc of docs) {
      try {
        const vector = await this.lanceDBService.generateEmbedding(doc.content);
        results.push({ ...doc, vector });
      } catch (error) {
        this.logger.warn(`Failed to generate embedding for ${doc.fileName}`);
      }
    }

    return results;
  }

  /**
   * Calculate cosine similarity between two vectors
   */
  private cosineSimilarity(a: number[], b: number[]): number {
    if (a.length !== b.length) {
      throw new Error('Vectors must have the same dimension');
    }

    let dotProduct = 0;
    let normA = 0;
    let normB = 0;

    for (let i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    const denominator = Math.sqrt(normA) * Math.sqrt(normB);
    if (denominator === 0) return 0;

    return dotProduct / denominator;
  }

  /**
   * Find duplicate groups using similarity threshold
   * Uses Union-Find for efficient grouping
   */
  private findDuplicateGroups(
    docs: Array<SearchResult & { vector: number[] }>,
    threshold: number,
  ): DuplicateGroup[] {
    const n = docs.length;

    // Union-Find data structures
    const parent: number[] = Array.from({ length: n }, (_, i) => i);
    const rank: number[] = new Array(n).fill(0);

    // Find with path compression
    const find = (x: number): number => {
      if (parent[x] !== x) {
        parent[x] = find(parent[x]);
      }
      return parent[x];
    };

    // Union by rank
    const union = (x: number, y: number): void => {
      const px = find(x);
      const py = find(y);
      if (px === py) return;

      if (rank[px] < rank[py]) {
        parent[px] = py;
      } else if (rank[px] > rank[py]) {
        parent[py] = px;
      } else {
        parent[py] = px;
        rank[px]++;
      }
    };

    // Store similarities for later use
    const similarities: Map<string, number> = new Map();

    // Compare all pairs and union similar ones
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const similarity = this.cosineSimilarity(docs[i].vector, docs[j].vector);

        if (similarity >= threshold) {
          union(i, j);
          similarities.set(`${i}-${j}`, similarity);
          similarities.set(`${j}-${i}`, similarity);
        }
      }
    }

    // Group documents by their root parent
    const groups: Map<number, number[]> = new Map();
    for (let i = 0; i < n; i++) {
      const root = find(i);
      if (!groups.has(root)) {
        groups.set(root, []);
      }
      groups.get(root)!.push(i);
    }

    // Convert to DuplicateGroup format (only groups with > 1 member)
    const duplicateGroups: DuplicateGroup[] = [];

    for (const [_, indices] of groups) {
      if (indices.length < 2) continue;

      // Sort by creation date (if available) or use first as primary
      const sortedIndices = [...indices];
      const primary = docs[sortedIndices[0]];
      const duplicates = sortedIndices.slice(1).map((idx) => {
        const doc = docs[idx];
        const sim = similarities.get(`${sortedIndices[0]}-${idx}`) || threshold;
        return {
          filePath: doc.filePath,
          fileName: doc.fileName,
          mediaType: doc.mediaType,
          similarity: Math.round(sim * 1000) / 1000,
        };
      });

      // Calculate average similarity
      const totalSim = duplicates.reduce((sum, d) => sum + d.similarity, 0);
      const avgSim = duplicates.length > 0 ? totalSim / duplicates.length : 1;

      duplicateGroups.push({
        primary: {
          filePath: primary.filePath,
          fileName: primary.fileName,
          mediaType: primary.mediaType,
        },
        duplicates,
        averageSimilarity: Math.round(avgSim * 1000) / 1000,
      });
    }

    // Sort by number of duplicates (descending)
    duplicateGroups.sort((a, b) => b.duplicates.length - a.duplicates.length);

    return duplicateGroups;
  }

  /**
   * Generate delete actions for duplicate files
   * Keeps the primary file and suggests deleting duplicates
   */
  async generateDedupActions(
    groups: DuplicateGroup[],
  ): Promise<Array<{ type: 'delete'; filePath: string; reason: string }>> {
    const actions: Array<{ type: 'delete'; filePath: string; reason: string }> = [];

    for (const group of groups) {
      for (const dup of group.duplicates) {
        actions.push({
          type: 'delete',
          filePath: dup.filePath,
          reason: `Duplicate of "${group.primary.fileName}" (${Math.round(dup.similarity * 100)}% similar)`,
        });
      }
    }

    return actions;
  }
}
