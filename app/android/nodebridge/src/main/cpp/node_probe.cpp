#include <jni.h>
#include <node.h>

#include <string>
#include <vector>

extern "C" JNIEXPORT jstring JNICALL
Java_io_github_guog962464_aggregate_nodeprobe_NodeProbeService_nativeHeaderVersion(
    JNIEnv* env, jclass) {
  return env->NewStringUTF(NODE_VERSION);
}

extern "C" JNIEXPORT jint JNICALL
Java_io_github_guog962464_aggregate_nodeprobe_NodeProbeService_nativeStart(
    JNIEnv* env, jclass, jstring entry, jstring output, jint delay_ms,
    jstring events, jboolean fail) {
  const char* entry_chars = env->GetStringUTFChars(entry, nullptr);
  const char* output_chars = env->GetStringUTFChars(output, nullptr);
  const char* event_chars = env->GetStringUTFChars(events, nullptr);
  std::vector<std::string> arguments = {
      "node", entry_chars, output_chars, std::to_string(delay_ms),
      event_chars, fail ? "1" : "0"};
  env->ReleaseStringUTFChars(entry, entry_chars);
  env->ReleaseStringUTFChars(output, output_chars);
  env->ReleaseStringUTFChars(events, event_chars);
  size_t storage_size = 0;
  for (const auto& argument : arguments) storage_size += argument.size() + 1;
  std::string argv_storage;
  argv_storage.reserve(storage_size);
  for (const auto& argument : arguments) {
    argv_storage.append(argument);
    argv_storage.push_back('\0');
  }
  std::vector<char*> argv;
  argv.reserve(arguments.size() + 1);
  size_t argument_offset = 0;
  for (const auto& argument : arguments) {
    argv.push_back(argv_storage.data() + argument_offset);
    argument_offset += argument.size() + 1;
  }
  argv.push_back(nullptr);
  const int result = node::Start(static_cast<int>(argv.size() - 1), argv.data());
  return result;
}
