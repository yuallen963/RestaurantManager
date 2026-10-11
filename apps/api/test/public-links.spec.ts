import { appleAppSiteAssociation, PublicLinksController } from '../src/public-links.controller';

describe('Plaid public links', () => {
  const controller = new PublicLinksController();

  it('serves the exact app identifier and preserves Plaid while adding auth links', () => {
    expect(controller.association()).toEqual(appleAppSiteAssociation);
    expect(appleAppSiteAssociation.applinks.details).toEqual([
      {
        appIDs: ['4R7CXGD5WK.com.restaurantprofit.restaurantProfitMobile'],
        components: [
          { '/': '/plaid/*' },
          { '/': '/verify-email' },
          { '/': '/reset-password' },
        ],
      },
    ]);
  });

  it('serves auth fallbacks without embedding a token value', () => {
    const verify = controller.verificationFallback();
    const reset = controller.resetPasswordFallback();
    expect(verify).toContain('/api/v1/auth/verify-email');
    expect(reset).toContain('/api/v1/auth/reset-password');
    expect(reset).toContain('type="password"');
    expect(verify).not.toContain('sensitive-token-value');
    expect(reset).not.toContain('sensitive-token-value');
  });

  it('serves a safe browser fallback without echoing request data', () => {
    const page = controller.plaidOAuthFallback();
    expect(page).toContain('Open ProfitLens');
    expect(page).not.toContain('token');
    expect(page).not.toContain('query');
  });
});
