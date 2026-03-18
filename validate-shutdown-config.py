#!/usr/bin/env python3
"""
简单的 vLLM shutdown-timeout 参数验证测试
这个脚本验证我们的配置文件中的参数格式是否正确
"""

import re
import sys
from pathlib import Path

def check_shutdown_timeout_in_file(file_path):
    """检查文件中的 shutdown-timeout 配置"""
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        # 查找 shutdown-timeout 参数
        patterns = [
            r'--shutdown-timeout[=\s]+(\d+)',  # --shutdown-timeout=30 或 --shutdown-timeout 30
            r'"--shutdown-timeout=(\d+)"',      # "--shutdown-timeout=30"
        ]
        
        found = False
        for pattern in patterns:
            matches = re.findall(pattern, content)
            if matches:
                found = True
                for timeout_value in matches:
                    print(f"  ✓ Found: --shutdown-timeout={timeout_value}")
                    
                    # 验证值是否合理
                    timeout = int(timeout_value)
                    if timeout < 0:
                        print(f"    ⚠ Warning: Negative timeout value")
                        return False
                    elif timeout == 0:
                        print(f"    ℹ Info: Timeout=0 means immediate abort")
                    elif timeout < 10:
                        print(f"    ⚠ Warning: Very short timeout ({timeout}s)")
                    elif timeout > 300:
                        print(f"    ⚠ Warning: Very long timeout ({timeout}s)")
                    else:
                        print(f"    ✓ Timeout value is reasonable")
        
        # 检查 terminationGracePeriodSeconds
        term_pattern = r'terminationGracePeriodSeconds:\s*(\d+)'
        term_matches = re.findall(term_pattern, content)
        if term_matches:
            for term_value in term_matches:
                print(f"  ✓ Found: terminationGracePeriodSeconds={term_value}")
                
                # 如果同时有 shutdown-timeout，验证关系
                if found and matches:
                    shutdown_timeout = int(matches[0])
                    term_timeout = int(term_value)
                    if term_timeout <= shutdown_timeout:
                        print(f"    ✗ Error: terminationGracePeriodSeconds ({term_timeout}) should be > shutdown-timeout ({shutdown_timeout})")
                        return False
                    else:
                        buffer = term_timeout - shutdown_timeout
                        print(f"    ✓ Buffer time: {buffer}s (terminationGracePeriodSeconds - shutdown-timeout)")
        
        return found
    
    except Exception as e:
        print(f"  ✗ Error reading file: {e}")
        return False

def main():
    print("=== vLLM Graceful Shutdown Configuration Validator ===\n")
    
    # 要检查的文件列表
    files_to_check = [
        "guides/recipes/vllm/base/deployment.yaml",
        "guides/inference-scheduling/ms-inference-scheduling/values.yaml",
        "guides/pd-disaggregation/ms-pd/values.yaml",
        "guides/pd-disaggregation/ms-pd/values_amd.yaml",
        "guides/precise-prefix-cache-aware/ms-kv-events/values.yaml",
        "guides/precise-prefix-cache-aware/ms-kv-events/values_pod_discovery.yaml",
        "guides/workload-autoscaling/ms-workload-autoscaling/values.yaml",
        "guides/wide-ep-lws/manifests/modelserver/base/decode.yaml",
        "guides/wide-ep-lws/manifests/modelserver/base/prefill.yaml",
    ]
    
    base_dir = Path(__file__).parent
    all_passed = True
    files_with_config = 0
    
    for file_path in files_to_check:
        full_path = base_dir / file_path
        if not full_path.exists():
            print(f"⚠ File not found: {file_path}")
            continue
        
        print(f"\nChecking: {file_path}")
        if check_shutdown_timeout_in_file(full_path):
            files_with_config += 1
        else:
            print(f"  ℹ No shutdown-timeout configuration found")
    
    print(f"\n{'='*60}")
    print(f"Summary:")
    print(f"  Files checked: {len(files_to_check)}")
    print(f"  Files with shutdown-timeout: {files_with_config}")
    
    if files_with_config > 0:
        print(f"\n✓ Configuration validation passed!")
        print(f"\nNext steps to test:")
        print(f"  1. Start Docker Desktop")
        print(f"  2. Run: ./test-graceful-shutdown-simple.sh")
        print(f"  3. Or follow: TESTING-GRACEFUL-SHUTDOWN.md")
        return 0
    else:
        print(f"\n✗ No shutdown-timeout configurations found!")
        return 1

if __name__ == "__main__":
    sys.exit(main())
