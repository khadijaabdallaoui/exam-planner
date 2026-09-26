import { Controller, Get, Post, Body } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Controller('rooms')
export class RoomsController {
  constructor(private prisma: PrismaService) {}

  @Get()
  findAll() {
    return this.prisma.room.findMany({ orderBy: { name: 'asc' } });
  }

  @Post()
  create(@Body() body: { name: string; building?: string; capacity: number }) {
    return this.prisma.room.create({ data: body });
  }
}