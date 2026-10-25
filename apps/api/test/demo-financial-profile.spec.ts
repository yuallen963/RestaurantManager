import {
  demoDowntownLocationId,
  demoExpenseAmount,
  demoMainLocationId,
  downtownExpenseRecipe,
  mainExpenseRecipe,
  monthlyCostFactor,
  recipeRatio,
} from '../prisma/demo-financial-profile';

describe('public demo financial profile', () => {
  it('keeps each location within a realistic operating cost range', () => {
    expect(recipeRatio(downtownExpenseRecipe)).toBeCloseTo(.865, 6);
    expect(recipeRatio(mainExpenseRecipe)).toBeCloseTo(.86, 6);
  });

  it.each([demoDowntownLocationId, demoMainLocationId])(
    'keeps historical monthly margins positive and varied for %s',
    (locationId) => {
      const recipe = locationId === demoDowntownLocationId
        ? downtownExpenseRecipe
        : mainExpenseRecipe;
      const margins = Array.from({ length: 12 }, (_, month) => {
        const date = new Date(Date.UTC(2026, month, 15, 12));
        return 1 - recipeRatio(recipe) * monthlyCostFactor(date, locationId);
      });
      expect(Math.min(...margins)).toBeGreaterThan(.12);
      expect(Math.max(...margins)).toBeLessThan(.16);
      expect(new Set(margins.map((margin) => margin.toFixed(4))).size).toBeGreaterThan(3);
    },
  );

  it('calculates stable, currency-precise amounts on repeated runs', () => {
    const date = new Date(Date.UTC(2026, 9, 25, 12));
    const first = demoExpenseAmount(3210.47, .285, date, demoDowntownLocationId);
    const second = demoExpenseAmount(3210.47, .285, date, demoDowntownLocationId);
    expect(first).toBe(second);
    expect(first).toBe(918.64);
  });
});
