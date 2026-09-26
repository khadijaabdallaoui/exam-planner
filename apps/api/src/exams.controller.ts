import { Body, Controller, Get, HttpException, HttpStatus, Post } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Controller('exams')
export class ExamsController {
  constructor(private prisma: PrismaService) {}

  @Get()
  findAll() {
    return this.prisma.exam.findMany({
      include: { room: true, module: true, professor: true, groups: { include: { group: true } } },
      orderBy: { startsAt: 'asc' },
    });
  }

  @Post()
  async create(
    @Body()
    body: {
      moduleId: string;
      roomId: string;
      professorId: string;
      startsAt: string;
      endsAt: string;
      groupIds: string[];
    },
  ) {
    try {
      return await this.prisma.$transaction(async (tx) => {
        const exam = await tx.exam.create({
          data: {
            moduleId: body.moduleId,
            roomId: body.roomId,
            professorId: body.professorId,
            startsAt: new Date(body.startsAt),
            endsAt: new Date(body.endsAt),
          },
        });

        for (const groupId of body.groupIds) {
          await tx.$executeRawUnsafe(
            `INSERT INTO exam_groups ("examId", "groupId") VALUES ($1, $2)`,
            exam.id,
            groupId,
          );
        }

        return exam;
      });
    } catch (error: any) {
      const message = error?.message ?? '';
      if (message.includes('exams_no_room_overlap')) {
        throw new HttpException('Cette salle est déjà occupée sur ce créneau.', HttpStatus.CONFLICT);
      }
      if (message.includes('exams_no_professor_overlap')) {
        throw new HttpException('Ce professeur a déjà un examen sur ce créneau.', HttpStatus.CONFLICT);
      }
      if (message.includes('exam_groups_no_group_overlap')) {
        throw new HttpException('Ce groupe a déjà un examen sur ce créneau.', HttpStatus.CONFLICT);
      }
      throw error;
    }
  }
}