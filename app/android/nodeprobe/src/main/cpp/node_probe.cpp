#include <jni.h>
#include <node.h>

#include <string>
#include <vector>

extern "C" JNIEXPORT jint JNICALL
Java_io_github_guog962464_aggregate_nodeprobe_NodeProbeService_nativeStart(
    JNIEnv* env, jclass, jstring entry, jstring output) {
  const char* entry_chars = env->GetStringUTFChars(entry, nullptr);
  const char* output_chars = env->GetStringUTFChars(output, nullptr);
  std::vector<std::string> arguments = {"node", entry_chars, output_chars};
  env->ReleaseStringUTFChars(entry, entry_chars);
  env->ReleaseStringUTFChars(output, output_chars);
  std::vector<char*> argv;
  for (auto& argument : arguments) argv.push_back(argument.data());
  return node::Start(static_cast<int>(argv.size()), argv.data());
}
