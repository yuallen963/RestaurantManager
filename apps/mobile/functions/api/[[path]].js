import { proxyApiRequest } from '../_shared/api_proxy.mjs';

export function onRequest(context) {
  return proxyApiRequest(context.request, context.env);
}
