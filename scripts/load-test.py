#!/usr/bin/env python3
"""
Load Test Script for Excalidraw Whiteboard Application
Simulates multiple concurrent users drawing on the whiteboard to trigger scaling
"""

import concurrent.futures
import requests
import time
import random
import sys
import signal
from datetime import datetime

# Configuration
TARGET_URL = "http://34.49.56.133/"
NUM_CONCURRENT_USERS = 5
REQUESTS_PER_USER = 10
DELAY_BETWEEN_REQUESTS = 2  # seconds
TOTAL_DURATION_SECONDS = 120

# Global tracking
start_time = None
stop_requested = False
successful_requests = 0
failed_requests = 0
total_latency = 0

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    global stop_requested
    stop_requested = True
    print("\n\n[!] Stop signal received. Gracefully shutting down...")

def log_message(message):
    """Print timestamped log message"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}] {message}")

def user_session(user_id):
    """
    Simulate a single user session
    - Load the application
    - Simulate drawing/interactions
    - Keep connection alive
    """
    global successful_requests, failed_requests, total_latency
    
    session = requests.Session()
    
    try:
        log_message(f"User {user_id}: Starting session")
        
        # Load main page
        try:
            response = session.get(TARGET_URL, timeout=10)
            if response.status_code == 200:
                successful_requests += 1
                total_latency += response.elapsed.total_seconds()
                log_message(f"User {user_id}: Loaded app ({response.elapsed.total_seconds():.2f}s)")
            else:
                failed_requests += 1
                log_message(f"User {user_id}: Got status {response.status_code}")
        except Exception as e:
            failed_requests += 1
            log_message(f"User {user_id}: Load failed - {str(e)}")
            return
        
        # Simulate user interactions (drawing, etc.)
        for req_num in range(REQUESTS_PER_USER):
            if stop_requested:
                log_message(f"User {user_id}: Received stop signal after {req_num} requests")
                break
            
            time.sleep(random.uniform(DELAY_BETWEEN_REQUESTS * 0.5, DELAY_BETWEEN_REQUESTS * 1.5))
            
            try:
                # Simulate various interactions
                response = session.get(TARGET_URL, timeout=10)
                if response.status_code == 200:
                    successful_requests += 1
                    total_latency += response.elapsed.total_seconds()
                else:
                    failed_requests += 1
                    log_message(f"User {user_id}: Request {req_num+1} got status {response.status_code}")
            except Exception as e:
                failed_requests += 1
                log_message(f"User {user_id}: Request {req_num+1} failed - {str(e)}")
        
        log_message(f"User {user_id}: Session completed ({REQUESTS_PER_USER} requests)")
        
    except Exception as e:
        log_message(f"User {user_id}: Session error - {str(e)}")
    finally:
        session.close()

def main():
    """Main load test orchestration"""
    global start_time, stop_requested, successful_requests, failed_requests, total_latency
    
    print("\n" + "="*80)
    print("       EXCALIDRAW WHITEBOARD LOAD TEST")
    print("="*80)
    print(f"\nConfiguration:")
    print(f"  Target: {TARGET_URL}")
    print(f"  Concurrent Users: {NUM_CONCURRENT_USERS}")
    print(f"  Requests per User: {REQUESTS_PER_USER}")
    print(f"  Delay Between Requests: {DELAY_BETWEEN_REQUESTS}s")
    print(f"  Total Duration: {TOTAL_DURATION_SECONDS}s")
    print(f"\nThis load test will:")
    print(f"  1. Simulate {NUM_CONCURRENT_USERS} concurrent users")
    print(f"  2. Each user will make {REQUESTS_PER_USER} requests")
    print(f"  3. Monitor resource consumption via Grafana")
    print(f"  4. Trigger horizontal pod autoscaling if enabled")
    print(f"\nWatch metrics in Grafana:")
    print(f"  CPU usage: Should spike to 60%+ on current replicas")
    print(f"  Memory usage: Should increase as load increases")
    print(f"  Pod count: Should increase from 2 to 4+ (if HPA enabled)")
    print(f"  Request rate: Should show {NUM_CONCURRENT_USERS}x spike")
    print("\n" + "="*80 + "\n")
    
    # Set signal handler for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        start_time = time.time()
        log_message(f"Starting load test with {NUM_CONCURRENT_USERS} concurrent users...")
        
        # Execute load test with thread pool
        with concurrent.futures.ThreadPoolExecutor(max_workers=NUM_CONCURRENT_USERS) as executor:
            futures = [
                executor.submit(user_session, user_id) 
                for user_id in range(1, NUM_CONCURRENT_USERS + 1)
            ]
            
            # Wait for all futures to complete or timeout
            try:
                completed, pending = concurrent.futures.wait(
                    futures, 
                    timeout=TOTAL_DURATION_SECONDS
                )
                
                if pending:
                    log_message(f"Cancelling {len(pending)} pending tasks due to timeout...")
                    for future in pending:
                        future.cancel()
                
                # Collect results
                for future in concurrent.futures.as_completed(futures):
                    try:
                        future.result()
                    except Exception as e:
                        log_message(f"Task error: {str(e)}")
                        
            except Exception as e:
                log_message(f"Executor error: {str(e)}")
        
        # Calculate and display results
        elapsed_time = time.time() - start_time
        total_requests = successful_requests + failed_requests
        
        print("\n" + "="*80)
        print("       LOAD TEST RESULTS")
        print("="*80)
        print(f"\nTest Duration: {elapsed_time:.2f} seconds")
        print(f"Total Requests: {total_requests}")
        print(f"Successful Requests: {successful_requests}")
        print(f"Failed Requests: {failed_requests}")
        
        if successful_requests > 0:
            avg_latency = total_latency / successful_requests
            print(f"Average Latency: {avg_latency:.3f} seconds")
            print(f"Requests/sec: {successful_requests / elapsed_time:.2f}")
            
            if avg_latency > 1.0:
                print(f"\n⚠️  WARNING: Average latency ({avg_latency:.3f}s) is high!")
                print(f"   This indicates the system is under heavy load.")
                print(f"   Check Grafana dashboard to see if pods are scaling up.")
            elif avg_latency < 0.5:
                print(f"\n✅ Latency is good ({avg_latency:.3f}s)")
                print(f"   System is handling load well.")
        
        if failed_requests > 0:
            failure_rate = (failed_requests / total_requests) * 100
            print(f"\n❌ Failure Rate: {failure_rate:.1f}%")
            if failure_rate > 10:
                print(f"   High failure rate! Check cluster health.")
        else:
            print(f"\n✅ No failures - System is stable!")
        
        print("\n" + "="*80)
        print("\nNext Steps:")
        print("  1. Check Grafana dashboard: kubectl port-forward -n monitoring svc/grafana 3001:3000")
        print("  2. Check pod scaling: kubectl get pods -n whiteboard -w")
        print("  3. Check HPA status: kubectl get hpa -n whiteboard")
        print("  4. View metrics: kubectl top nodes && kubectl top pods -n whiteboard")
        print("="*80 + "\n")
        
        return 0 if failed_requests == 0 else 1
        
    except KeyboardInterrupt:
        log_message("Load test interrupted by user")
        return 1
    except Exception as e:
        log_message(f"Error: {str(e)}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
