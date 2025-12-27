import ray
import time

ray.init()

@ray.remote(num_gpus=1)
def gpu_compute_task(task_id):
    print(f"Executing AI Task {task_id} on GPU hardware...")
    time.sleep(180) # Simulate 3 minutes of heavy training
    return f"Task {task_id} Complete"

# Trigger 4 GPUs (Karpenter will scale 2x-4x nodes depending on instance availability)
print("🚀 Triggering Neural Surge: Demanding 4 GPUs...")
results = ray.get([gpu_compute_task.remote(i) for i in range(4)])
print(results)