import { Module } from '@nestjs/common';
import { LanceDBService } from './lancedb.service';

@Module({
  providers: [LanceDBService],
  exports: [LanceDBService],
})
export class LanceDBModule {}
