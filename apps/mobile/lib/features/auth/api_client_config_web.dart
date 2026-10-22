import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

void configureApiClient(Dio client) {
  client.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
  client.options.headers['X-FundWell-Client'] = 'web';
}
