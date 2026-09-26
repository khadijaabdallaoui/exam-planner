import { Body, Controller, HttpException, HttpStatus, Post } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from './prisma.service';

@Controller('auth')
export class AuthController {
  constructor(
    private prisma: PrismaService,
    private jwt: JwtService,
  ) {}

  @Post('register')
  async register(
    @Body() body: { email: string; password: string; fullName: string; role: string },
  ) {
    const existing = await this.prisma.user.findUnique({ where: { email: body.email } });
    if (existing) {
      throw new HttpException('Cet email est déjà utilisé.', HttpStatus.CONFLICT);
    }

    const passwordHash = await bcrypt.hash(body.password, 10);
    const user = await this.prisma.user.create({
      data: {
        email: body.email,
        passwordHash,
        fullName: body.fullName,
        role: body.role as any,
      },
    });

    return { id: user.id, email: user.email, fullName: user.fullName, role: user.role };
  }

  @Post('login')
  async login(@Body() body: { email: string; password: string }) {
    const user = await this.prisma.user.findUnique({ where: { email: body.email } });
    if (!user) {
      throw new HttpException('Email ou mot de passe incorrect.', HttpStatus.UNAUTHORIZED);
    }

    const valid = await bcrypt.compare(body.password, user.passwordHash);
    if (!valid) {
      throw new HttpException('Email ou mot de passe incorrect.', HttpStatus.UNAUTHORIZED);
    }

    const token = await this.jwt.signAsync({ sub: user.id, role: user.role });
    return { access_token: token, user: { id: user.id, email: user.email, fullName: user.fullName, role: user.role } };
  }
}