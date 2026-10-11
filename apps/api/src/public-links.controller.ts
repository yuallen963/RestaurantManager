import { Controller, Get, Header } from '@nestjs/common';

export const appleAppSiteAssociation = {
  applinks: {
    details: [
      {
        appIDs: ['4R7CXGD5WK.com.restaurantprofit.restaurantProfitMobile'],
        components: [
          { '/': '/plaid/*' },
          { '/': '/verify-email' },
          { '/': '/reset-password' },
        ],
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

  @Get('verify-email')
  @Header('Content-Type', 'text/html; charset=utf-8')
  verificationFallback() {
    return authFallbackPage('Verify your FundWell email', 'verify');
  }

  @Get('reset-password')
  @Header('Content-Type', 'text/html; charset=utf-8')
  resetPasswordFallback() {
    return authFallbackPage('Reset your FundWell password', 'reset');
  }
}

function authFallbackPage(title: string, mode: 'verify' | 'reset') {
  const form = mode === 'reset' ? '<label>New password (12+ characters)<input id="password" type="password" minlength="12" autocomplete="new-password" required></label>' : '';
  const button = mode === 'verify' ? 'Verify email' : 'Reset password';
  const endpoint = mode === 'verify' ? 'verify-email' : 'reset-password';
  const payload = mode === 'verify' ? '{token}' : '{token,password:document.getElementById("password").value}';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head><body><main><h1>${title}</h1><p id="message">Open FundWell, or continue securely in your browser.</p>${form}<button id="submit" type="button">${button}</button></main><script>document.getElementById("submit").addEventListener("click",async()=>{const token=new URLSearchParams(location.search).get("token");if(!token){document.getElementById("message").textContent="This link is invalid or expired.";return}const response=await fetch("/api/v1/auth/${endpoint}",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(${payload})});document.getElementById("message").textContent=response.ok?"Complete. You can return to FundWell.":"This link is invalid or expired."})</script></body></html>`;
}
