import { Controller, Get, Header } from '@nestjs/common';

export const appleAppSiteAssociation = {
  applinks: {
    details: [
      {
        appIDs: ['4R7CXGD5WK.com.restaurantprofit.restaurantProfitMobile'],
        components: [{ '/': '/plaid/*' }],
      },
    ],
  },
};

@Controller()
export class PublicLinksController {
  @Get('.well-known/apple-app-site-association')
  @Header('Content-Type', 'application/json')
  association() {
    return appleAppSiteAssociation;
  }

  @Get('plaid/oauth')
  @Header('Content-Type', 'text/html; charset=utf-8')
  plaidOAuthFallback() {
    return '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Return to ProfitLens</title></head><body><main><h1>Return to ProfitLens</h1><p>Open ProfitLens to continue connecting your bank account.</p></main></body></html>';
  }
}
