import 'text_system_capability.dart';

class TextSystemCapabilityRegistry {
  TextSystemCapabilityRegistry([
    Iterable<TextSystemCapability> capabilities = const <TextSystemCapability>[],
  ]) {
    for (final capability in capabilities) {
      register(capability);
    }
  }

  final Map<String, TextSystemCapability> _capabilities =
      <String, TextSystemCapability>{};

  List<TextSystemCapability> get capabilities =>
      List.unmodifiable(_capabilities.values);

  void register(TextSystemCapability capability) {
    _capabilities[capability.id] = capability;
  }

  TextSystemCapability? byId(String id) => _capabilities[id];
}
