import { appleAppSiteAssociation, PublicLinksController } from '../src/public-links.controller';

describe('Plaid public links', () => {
  const controller = new PublicLinksController();

  it('serves the exact app identifier and only the Plaid universal-link path', () => {
    expect(controller.association()).toEqual(appleAppSiteAssociation);
    expect(appleAppSiteAssociation.applinks.details).toEqual([
      {
        appIDs: ['4R7CXGD5WK.com.restaurantprofit.restaurantProfitMobile'],
        components: [{ '/': '/plaid/*' }],
      },
    ]);
  });

  it('serves a safe browser fallback without echoing request data', () => {
    const page = controller.plaidOAuthFallback();
    expect(page).toContain('Open ProfitLens');
    expect(page).not.toContain('token');
    expect(page).not.toContain('query');
  });
});
