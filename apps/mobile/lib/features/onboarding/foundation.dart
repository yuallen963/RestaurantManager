import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show api;

class OnboardingState {
  const OnboardingState({
    required this.currentStep,
    required this.completed,
    required this.selectedDataSources,
    this.organizationName,
    this.locationName,
  });
  final int currentStep;
  final bool completed;
  final List<String> selectedDataSources;
  final String? organizationName, locationName;

  factory OnboardingState.fromJson(Map<String, dynamic> json) =>
      OnboardingState(
        currentStep: json['currentStep'] as int? ?? 1,
        completed: json['onboardingCompletedAt'] != null,
        selectedDataSources: (json['selectedDataSources'] as List? ?? const [])
            .cast<String>(),
        organizationName: (json['organization'] as Map?)?['name'] as String?,
        locationName: (json['restaurantLocation'] as Map?)?['name'] as String?,
      );
}

class OnboardingRepository {
  OnboardingRepository(this.dio);
  final Dio dio;
  Future<OnboardingState> get() async => OnboardingState.fromJson(
    Map<String, dynamic>.from((await dio.get('/onboarding')).data as Map),
  );
  Future<OnboardingState> progress(int step, List<String> sources) async =>
      OnboardingState.fromJson(
        Map<String, dynamic>.from(
          (await dio.patch(
                '/onboarding/progress',
                data: {'currentStep': step, 'selectedDataSources': sources},
              )).data
              as Map,
        ),
      );
  Future<OnboardingState> setup(Map<String, dynamic> data) async =>
      OnboardingState.fromJson(
        Map<String, dynamic>.from(
          (await dio.post('/onboarding/setup', data: data)).data as Map,
        ),
      );
  Future<OnboardingState> complete() async => OnboardingState.fromJson(
    Map<String, dynamic>.from(
      (await dio.post('/onboarding/complete')).data as Map,
    ),
  );
}

final onboardingRepositoryProvider = Provider(
  (ref) => OnboardingRepository(ref.watch(api)),
);
final onboardingStateProvider = FutureProvider(
  (ref) => ref.watch(onboardingRepositoryProvider).get(),
);
