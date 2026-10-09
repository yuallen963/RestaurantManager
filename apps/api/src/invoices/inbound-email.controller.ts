import { Body, Controller, Get, Post, Query, UploadedFiles, UseGuards, UseInterceptors } from '@nestjs/common';
import { AnyFilesInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { InboundAttachment, InboundEmailService, MailgunInboundBody } from './inbound-email.service';

@ApiTags('invoice-email')
@Controller('invoice-email')
export class InvoiceEmailController {
  constructor(private readonly inbound: InboundEmailService) {}

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('address')
  address(@CurrentUser() user: { sub: string }, @Query('restaurantLocationId') restaurantLocationId: string) {
    return this.inbound.address(user.sub, restaurantLocationId);
  }

  @Post('webhooks/mailgun')
  @UseInterceptors(AnyFilesInterceptor({ limits: { files: 20, fileSize: 16 * 1024 * 1024, fields: 100, fieldSize: 1024 * 1024 } }))
  webhook(@Body() body: MailgunInboundBody, @UploadedFiles() files: InboundAttachment[] = []) {
    return this.inbound.ingest(body, files);
  }
}
