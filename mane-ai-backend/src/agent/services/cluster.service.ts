import { Injectable, Logger } from '@nestjs/common';
import { LanceDBService, SearchResult } from '../../lancedb';
import { ConfigService } from '../../config';
import { ChatOllama } from '@langchain/ollama';
import { HumanMessage } from '@langchain/core/messages';
import { FileAction } from '../tools';
import * as path from 'path';

/**
 * Cluster Result
 * A group of files that belong together based on content similarity
 */
export interface ClusterResult {
  /** Cluster ID */
  id: number;
  /** AI-generated label for the cluster */
  label: string;
  /** Suggested folder name */
  suggestedFolderName: string;
  /** Files in this cluster */
  files: Array<{
    filePath: string;
    fileName: string;
    mediaType: string;
  }>;
  /** Keywords/themes found in this cluster */
  keywords: string[];
}

@Injectable()
export class ClusterService {
  private readonly logger = new Logger(ClusterService.name);
  private chatModel: ChatOllama | null = null;

  constructor(
    private readonly lanceDBService: LanceDBService,
    private readonly configService: ConfigService,
  ) {
    this.initializeModel();
  }

  private async initializeModel(): Promise<void> {
    const ollamaUrl = this.configService.getOllamaUrl();
    const ollamaModel = this.configService.getOllamaModel();

    this.chatModel = new ChatOllama({
      baseUrl: ollamaUrl,
      model: ollamaModel,
      temperature: 0.3,
    });
  }

  /**
   * Organize files using K-means clustering
   */
  async organizeFiles(maxClusters: number = 10): Promise<ClusterResult[]> {
    this.logger.log('Starting file organization with clustering');

    // Get all documents
    const docs = await this.lanceDBService.getAllDocuments();

    if (docs.length < 3) {
      this.logger.log('Not enough documents to cluster');
      return [];
    }

    // Get vectors for all documents
    const docsWithVectors = await this.getDocumentsWithVectors(docs);

    if (docsWithVectors.length < 3) {
      return [];
    }

    // Determine optimal K using elbow method (simplified)
    const k = Math.min(
      Math.max(2, Math.floor(Math.sqrt(docsWithVectors.length / 2))),
      maxClusters,
    );

    this.logger.log(`Clustering ${docsWithVectors.length} documents into ${k} clusters`);

    // Run K-means clustering
    const clusters = this.kMeans(docsWithVectors, k);

    // Label clusters using LLM
    const labeledClusters = await this.labelClusters(clusters, docsWithVectors);

    this.logger.log(`Generated ${labeledClusters.length} clusters`);
    return labeledClusters;
  }

  /**
   * Get documents with their vectors
   */
  private async getDocumentsWithVectors(
    docs: SearchResult[],
  ): Promise<Array<SearchResult & { vector: number[] }>> {
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
   * K-means clustering implementation
   */
  private kMeans(
    docs: Array<SearchResult & { vector: number[] }>,
    k: number,
    maxIterations: number = 100,
  ): Map<number, number[]> {
    const n = docs.length;
    const dim = docs[0].vector.length;

    // Initialize centroids using k-means++
    const centroids: number[][] = this.initializeCentroids(docs, k);

    // Cluster assignments
    let assignments: number[] = new Array(n).fill(-1);

    for (let iter = 0; iter < maxIterations; iter++) {
      // Assign points to nearest centroid
      const newAssignments: number[] = [];
      for (let i = 0; i < n; i++) {
        let minDist = Infinity;
        let minCluster = 0;

        for (let c = 0; c < k; c++) {
          const dist = this.euclideanDistance(docs[i].vector, centroids[c]);
          if (dist < minDist) {
            minDist = dist;
            minCluster = c;
          }
        }

        newAssignments.push(minCluster);
      }

      // Check for convergence
      let changed = false;
      for (let i = 0; i < n; i++) {
        if (assignments[i] !== newAssignments[i]) {
          changed = true;
          break;
        }
      }

      assignments = newAssignments;

      if (!changed) {
        this.logger.log(`K-means converged after ${iter + 1} iterations`);
        break;
      }

      // Update centroids
      for (let c = 0; c < k; c++) {
        const clusterPoints = docs.filter((_, i) => assignments[i] === c);
        if (clusterPoints.length === 0) continue;

        const newCentroid = new Array(dim).fill(0);
        for (const point of clusterPoints) {
          for (let d = 0; d < dim; d++) {
            newCentroid[d] += point.vector[d];
          }
        }
        for (let d = 0; d < dim; d++) {
          newCentroid[d] /= clusterPoints.length;
        }
        centroids[c] = newCentroid;
      }
    }

    // Group documents by cluster
    const clusters: Map<number, number[]> = new Map();
    for (let i = 0; i < n; i++) {
      const cluster = assignments[i];
      if (!clusters.has(cluster)) {
        clusters.set(cluster, []);
      }
      clusters.get(cluster)!.push(i);
    }

    return clusters;
  }

  /**
   * Initialize centroids using k-means++
   */
  private initializeCentroids(
    docs: Array<SearchResult & { vector: number[] }>,
    k: number,
  ): number[][] {
    const centroids: number[][] = [];
    const n = docs.length;

    // Choose first centroid randomly
    const firstIdx = Math.floor(Math.random() * n);
    centroids.push([...docs[firstIdx].vector]);

    // Choose remaining centroids with probability proportional to distance squared
    for (let c = 1; c < k; c++) {
      const distances: number[] = [];
      let totalDist = 0;

      for (let i = 0; i < n; i++) {
        let minDist = Infinity;
        for (const centroid of centroids) {
          const dist = this.euclideanDistance(docs[i].vector, centroid);
          minDist = Math.min(minDist, dist);
        }
        distances.push(minDist * minDist);
        totalDist += minDist * minDist;
      }

      // Weighted random selection
      let rand = Math.random() * totalDist;
      for (let i = 0; i < n; i++) {
        rand -= distances[i];
        if (rand <= 0) {
          centroids.push([...docs[i].vector]);
          break;
        }
      }

      // Fallback if no centroid selected
      if (centroids.length <= c) {
        const idx = Math.floor(Math.random() * n);
        centroids.push([...docs[idx].vector]);
      }
    }

    return centroids;
  }

  /**
   * Calculate Euclidean distance between two vectors
   */
  private euclideanDistance(a: number[], b: number[]): number {
    let sum = 0;
    for (let i = 0; i < a.length; i++) {
      const diff = a[i] - b[i];
      sum += diff * diff;
    }
    return Math.sqrt(sum);
  }

  /**
   * Label clusters using LLM
   */
  private async labelClusters(
    clusters: Map<number, number[]>,
    docs: Array<SearchResult & { vector: number[] }>,
  ): Promise<ClusterResult[]> {
    const results: ClusterResult[] = [];

    for (const [clusterId, indices] of clusters) {
      if (indices.length === 0) continue;

      const clusterDocs = indices.map((i) => docs[i]);

      // Extract file info for the cluster
      const files = clusterDocs.map((d) => ({
        filePath: d.filePath,
        fileName: d.fileName,
        mediaType: d.mediaType,
      }));

      // Get sample content for labeling
      const sampleContent = clusterDocs
        .slice(0, 5)
        .map((d) => {
          const preview = d.content.length > 200
            ? d.content.substring(0, 200) + '...'
            : d.content;
          return `- ${d.fileName}: ${preview}`;
        })
        .join('\n');

      // Use LLM to generate label
      let label = `Cluster ${clusterId + 1}`;
      let suggestedFolderName = `cluster_${clusterId + 1}`;
      let keywords: string[] = [];

      if (this.chatModel) {
        try {
          const prompt = `Analyze these files and provide:
1. A short descriptive label (3-5 words)
2. A suggested folder name (lowercase, underscores, no spaces)
3. 3-5 keywords describing the content

Files in this cluster:
${sampleContent}

Respond in this exact format:
Label: [your label]
Folder: [folder_name]
Keywords: [keyword1, keyword2, keyword3]`;

          const response = await this.chatModel.invoke([new HumanMessage(prompt)]);
          const content = typeof response.content === 'string'
            ? response.content
            : JSON.stringify(response.content);

          // Parse response
          const labelMatch = content.match(/Label:\s*(.+)/i);
          const folderMatch = content.match(/Folder:\s*(\S+)/i);
          const keywordsMatch = content.match(/Keywords:\s*(.+)/i);

          if (labelMatch) label = labelMatch[1].trim();
          if (folderMatch) suggestedFolderName = folderMatch[1].trim().toLowerCase().replace(/[^a-z0-9_]/g, '_');
          if (keywordsMatch) {
            keywords = keywordsMatch[1]
              .split(',')
              .map((k) => k.trim())
              .filter((k) => k.length > 0);
          }
        } catch (error) {
          this.logger.warn(`Failed to label cluster ${clusterId}: ${error}`);
        }
      }

      results.push({
        id: clusterId,
        label,
        suggestedFolderName,
        files,
        keywords,
      });
    }

    // Sort by number of files (descending)
    results.sort((a, b) => b.files.length - a.files.length);

    return results;
  }

  /**
   * Generate file actions to organize files into cluster folders
   */
  async generateOrganizeActions(
    clusters: ClusterResult[],
    targetFolder?: string,
  ): Promise<FileAction[]> {
    const actions: FileAction[] = [];
    const baseFolder = targetFolder || path.join(process.env.HOME || '~', 'Organized');

    // Create folder actions
    for (const cluster of clusters) {
      if (cluster.files.length < 2) continue; // Skip single-file clusters

      const folderPath = path.join(baseFolder, cluster.suggestedFolderName);

      // Create folder action
      actions.push({
        id: `create_${cluster.id}_${Date.now()}`,
        type: 'createFolder',
        destinationPath: folderPath,
        requiresPermission: baseFolder,
        description: `Create folder "${cluster.suggestedFolderName}" for ${cluster.label}`,
      });

      // Move file actions
      for (const file of cluster.files) {
        const destPath = path.join(folderPath, file.fileName);
        actions.push({
          id: `move_${cluster.id}_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`,
          type: 'move',
          sourcePath: file.filePath,
          destinationPath: destPath,
          requiresPermission: folderPath,
          description: `Move "${file.fileName}" to ${cluster.suggestedFolderName}`,
        });
      }
    }

    return actions;
  }
}
