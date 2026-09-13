import subprocess
import os
import sys


def compile_c(source_file, output_file=None):
    if output_file is None:
        # 去掉 .c 后缀作为可执行文件名
        output_file = os.path.splitext(source_file)[0]

    result = subprocess.run(
        ["gcc", source_file, "-o", output_file, "-Wall", "-O2"],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print("Compile failed: ")
        print(result.stderr)
        return None
    print(f"Compile successful: {output_file}")
    return output_file


def run_c(executable, args=None):
    """运行编译后的可执行文件，并实时输出结果"""
    cmd = [executable] + (args or [])
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True
    )
    print("Program output:")
    print(result.stdout, end="")
    if result.stderr:
        print("Error output:", file=sys.stderr)
        print(result.stderr, end="", file=sys.stderr)
    print(f"\nExit code: {result.returncode}")
    return result.returncode


if __name__ == "__main__":
    c_file = sys.argv[1] if len(sys.argv) > 1 else "hello.c"
    extra_args = sys.argv[2:]

    exe = compile_c(c_file)
    if exe:
        run_c(exe, extra_args)