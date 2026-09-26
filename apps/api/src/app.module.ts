import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { PrismaService } from './prisma.service';
import { RoomsController } from './rooms.controller';
import { ExamsController } from './exams.controller';

@Module({
  imports: [],
  controllers: [AppController, RoomsController, ExamsController],
  providers: [AppService, PrismaService],
})
export class AppModule {}