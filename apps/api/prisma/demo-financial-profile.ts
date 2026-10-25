export type DemoExpenseRecipe = readonly [
  slug: string,
  ratio: number,
  vendorName: string | null,
  description: string,
];

export const demoOrganizationId = '00000000-0000-4000-8000-000000000001';
export const demoDowntownLocationId = '00000000-0000-4000-8000-000000000002';
export const demoMainLocationId = '00000000-0000-4000-8000-000000000004';

// Sustainable synthetic operating mixes. Food, beverage, labor, payroll,
// occupancy, and processing costs remain explicit rather than being hidden in
// a balancing category. Small deterministic monthly movement keeps the demo
// believable while producing a healthy restaurant-scale margin.
export const downtownExpenseRecipe: readonly DemoExpenseRecipe[] = [
  ['food', .285, 'sysco', 'Food inventory'],
  ['labor', .295, 'adp', 'Hourly and salaried labor'],
  ['beverage', .03, 'us foods', 'Beverage inventory'],
  ['payroll-taxes', .028, 'adp', 'Payroll taxes'],
  ['rent', .075, 'main street properties', 'Restaurant occupancy'],
  ['utilities', .024, 'dte energy', 'Electric and gas service'],
  ['delivery-fees', .035, 'doordash', 'Delivery marketplace fees'],
  ['merchant-fees', .028, 'toast', 'Card processing'],
  ['supplies', .014, 'restaurant depot', 'Operating supplies'],
  ['insurance', .008, 'harbor insurance', 'Business insurance'],
  ['repairs-maintenance', .008, null, 'Repairs and maintenance'],
  ['marketing', .008, 'brightline marketing', 'Local marketing'],
  ['software-subscriptions', .004, 'toast', 'Restaurant software'],
  ['taxes', .012, null, 'Local business taxes'],
  ['professional-services', .004, null, 'Professional services'],
  ['equipment', .007, 'restaurant depot', 'Small equipment'],
];

export const mainExpenseRecipe: readonly DemoExpenseRecipe[] = [
  ['food', .287, 'thai specialty produce', 'Thai ingredients and fresh produce'],
  ['labor', .286, 'adp', 'Front and back of house labor'],
  ['beverage', .032, 'gordon food service', 'Beverage inventory'],
  ['payroll-taxes', .029, 'adp', 'Payroll taxes'],
  ['rent', .075, 'main street properties', 'Restaurant occupancy'],
  ['utilities', .025, 'dte energy', 'Electric and gas service'],
  ['delivery-fees', .035, 'doordash', 'Delivery marketplace fees'],
  ['merchant-fees', .029, 'toast', 'Card processing'],
  ['supplies', .014, 'gordon food service', 'Operating supplies'],
  ['insurance', .008, 'harbor insurance', 'Business insurance'],
  ['repairs-maintenance', .007, null, 'Repairs and maintenance'],
  ['marketing', .007, 'brightline marketing', 'Local marketing'],
  ['software-subscriptions', .004, 'toast', 'Restaurant software'],
  ['taxes', .012, null, 'Local business taxes'],
  ['professional-services', .004, null, 'Professional services'],
  ['equipment', .006, 'metro asian foods', 'Kitchen equipment and smallwares'],
];

export const recipeForDemoLocation = (locationId: string) => {
  if (locationId === demoDowntownLocationId) return downtownExpenseRecipe;
  if (locationId === demoMainLocationId) return mainExpenseRecipe;
  throw new Error(`Unknown public demo location: ${locationId}`);
};

export const monthlyCostFactor = (date: Date, locationId: string) => {
  const salt = locationId === demoDowntownLocationId ? 2 : locationId === demoMainLocationId ? 4 : NaN;
  if (Number.isNaN(salt)) throw new Error(`Unknown public demo location: ${locationId}`);
  const monthKey = date.getUTCFullYear() * 12 + date.getUTCMonth();
  return 1 + ((((monthKey * 17 + salt) % 7) - 3) * .004);
};

export const recipeRatio = (recipe: readonly DemoExpenseRecipe[]) =>
  recipe.reduce((sum, [, ratio]) => sum + ratio, 0);

export const demoExpenseAmount = (
  revenue: number,
  ratio: number,
  date: Date,
  locationId: string,
) => Math.round(revenue * ratio * monthlyCostFactor(date, locationId) * 100) / 100;
