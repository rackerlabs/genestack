#!/usr/bin/env python3
"""
Complete workflow: Set expiration on objects, then monitor and delete empty containers.

This script combines:
1. Setting X-Delete-At headers on all objects in containers
2. Monitoring containers until they're empty
3. Automatically deleting empty containers
"""

import sys
import os
import time
import argparse
from datetime import datetime, timedelta
import swiftclient
from swiftclient.exceptions import ClientException


def get_swift_connection():
    """Create Swift connection from environment variables"""
    auth_url = os.environ.get("OS_AUTH_URL")
    username = os.environ.get("OS_USERNAME")
    password = os.environ.get("OS_PASSWORD")
    project_name = os.environ.get("OS_PROJECT_NAME")
    project_domain = os.environ.get("OS_PROJECT_DOMAIN_NAME", "Default")
    user_domain = os.environ.get("OS_USER_DOMAIN_NAME", "Default")

    if not all([auth_url, username, password, project_name]):
        print("Error: Missing OpenStack credentials")
        print("Please source your openrc file")
        sys.exit(1)

    try:
        conn = swiftclient.Connection(
            authurl=auth_url,
            user=username,
            key=password,
            os_options={
                "project_name": project_name,
                "project_domain_name": project_domain,
                "user_domain_name": user_domain,
            },
            auth_version="3",
        )
        return conn
    except Exception as e:
        print(f"Error connecting to Swift: {e}")
        sys.exit(1)


def calculate_delete_timestamp(
    seconds=None, minutes=None, hours=None, days=None, months=None
):
    """Calculate Unix timestamp for deletion"""
    total_seconds = 0

    if seconds:
        total_seconds += seconds
    if minutes:
        total_seconds += minutes * 60
    if hours:
        total_seconds += hours * 3600
    if days:
        total_seconds += days * 86400
    if months:
        total_seconds += months * 30 * 86400

    if total_seconds == 0:
        total_seconds = 3600  # Default: 1 hour

    return int(time.time() + total_seconds), total_seconds


def format_duration(seconds):
    """Format seconds into human-readable duration"""
    parts = []

    months = seconds // (30 * 86400)
    seconds %= 30 * 86400
    if months > 0:
        parts.append(f"{months} month(s)")

    days = seconds // 86400
    seconds %= 86400
    if days > 0:
        parts.append(f"{days} day(s)")

    hours = seconds // 3600
    seconds %= 3600
    if hours > 0:
        parts.append(f"{hours} hour(s)")

    minutes = seconds // 60
    seconds %= 60
    if minutes > 0:
        parts.append(f"{minutes} minute(s)")

    if seconds > 0:
        parts.append(f"{seconds} second(s)")

    return " ".join(parts) if parts else "0 seconds"


def set_expiration_on_container(conn, container, delete_timestamp, verbose=False):
    """Set X-Delete-At on all objects in a container"""
    print(f"\n{'=' * 70}")
    print(f"Setting expiration on container: {container}")
    print("=" * 70)

    try:
        _, objects = conn.get_container(container)
        object_count = len(objects)

        if object_count == 0:
            print(f"⚠️  Container is already empty")
            return 0, 0

        print(f"Found {object_count} objects")
        print()

        succeeded = 0
        failed = 0

        for i, obj in enumerate(objects, 1):
            obj_name = obj["name"]

            try:
                headers = {"X-Delete-At": str(delete_timestamp)}
                conn.post_object(container, obj_name, headers=headers)

                if verbose:
                    print(f"✓ [{i}/{object_count}] {obj_name}")

                succeeded += 1
            except ClientException as e:
                if e.http_status == 404:
                    if verbose:
                        print(f"⚠️  [{i}/{object_count}] Skipped (404): {obj_name}")
                    succeeded += 1  # Don't count as failure
                else:
                    print(f"✗ [{i}/{object_count}] Failed: {obj_name} - {e}")
                    failed += 1
            except Exception as e:
                print(f"✗ [{i}/{object_count}] Error: {obj_name} - {e}")
                failed += 1

            # Progress indicator
            if not verbose and i % 100 == 0:
                print(f"Progress: {i}/{object_count} objects processed")

        print()
        print(f"✓ Expiration set on {succeeded} objects")
        if failed > 0:
            print(f"✗ Failed: {failed} objects")

        return succeeded, failed

    except ClientException as e:
        print(f"✗ Error accessing container: {e}")
        return 0, 0


def check_container_status(conn, container):
    """Check if container is empty"""
    try:
        headers, objects = conn.get_container(container)
        object_count = int(headers.get("x-container-object-count", len(objects)))
        return object_count, True
    except ClientException as e:
        if e.http_status == 404:
            return 0, False
        else:
            raise


def delete_container(conn, container):
    """Delete an empty container"""
    try:
        conn.delete_container(container)
        return True, "Container deleted successfully"
    except ClientException as e:
        if e.http_status == 409:
            return False, "Container not empty"
        elif e.http_status == 404:
            return False, "Container does not exist"
        else:
            return False, f"Error: {e}"


def monitor_and_cleanup(
    conn, containers, check_interval=60, max_wait=3600, verbose=False
):
    """Monitor containers and delete when empty"""
    print(f"\n{'=' * 70}")
    print("Monitoring containers for deletion")
    print("=" * 70)
    print()

    start_time = time.time()
    containers_to_monitor = set(containers)
    deleted_containers = []

    iteration = 0

    while containers_to_monitor:
        iteration += 1
        elapsed = int(time.time() - start_time)

        if elapsed > max_wait:
            print(f"\nMaximum wait time ({max_wait}s) exceeded")
            print(f"Remaining containers: {len(containers_to_monitor)}")
            for container in containers_to_monitor:
                obj_count, exists = check_container_status(conn, container)
                if exists:
                    print(f"  - {container}: {obj_count} objects remaining")
            break

        print(
            f"\n[{datetime.now().strftime('%H:%M:%S')}] Check #{iteration} (elapsed: {elapsed}s)"
        )
        print("-" * 70)

        containers_checked = list(containers_to_monitor)

        for container in containers_checked:
            obj_count, exists = check_container_status(conn, container)

            if not exists:
                print(f"✓ {container}: Already deleted")
                containers_to_monitor.remove(container)
                continue

            if obj_count == 0:
                print(f"✓ {container}: Empty - deleting...")
                success, message = delete_container(conn, container)

                if success:
                    print(f"  ✓ {message}")
                    containers_to_monitor.remove(container)
                    deleted_containers.append(container)
                else:
                    print(f"  ✗ {message}")
            else:
                print(f"⏳ {container}: {obj_count} objects remaining")

        if containers_to_monitor:
            print(f"\nWaiting {check_interval} seconds before next check...")
            print(f"Containers remaining: {len(containers_to_monitor)}")
            time.sleep(check_interval)

    return deleted_containers


def main():
    parser = argparse.ArgumentParser(
        description="Complete workflow: Set expiration and cleanup containers",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Set 5-minute expiration and auto-cleanup
  %(prog)s -c freezer-bkp-lvm -m 5 --cleanup
  
  # Multiple containers with 1-hour expiration
  %(prog)s -c freezer-daily -c freezer-weekly -H 1 --cleanup
  
  # Set expiration only (no cleanup)
  %(prog)s -c freezer-bkp-lvm -d 7
  
  # Cleanup with custom monitoring interval
  %(prog)s -c freezer-bkp-lvm -m 5 --cleanup --check-interval 30
        """,
    )

    parser.add_argument(
        "-c",
        "--container",
        action="append",
        required=True,
        dest="containers",
        help="Container name (can be specified multiple times)",
    )

    # Time options
    parser.add_argument("-s", "--seconds", type=int, help="Delete after N seconds")
    parser.add_argument("-m", "--minutes", type=int, help="Delete after N minutes")
    parser.add_argument("-H", "--hours", type=int, help="Delete after N hours")
    parser.add_argument("-d", "--days", type=int, help="Delete after N days")
    parser.add_argument(
        "-M", "--months", type=int, help="Delete after N months (30 days each)"
    )
    parser.add_argument(
        "-t", "--delete-at", type=int, help="Delete at specific Unix timestamp"
    )

    # Cleanup options
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="Monitor and delete containers when empty",
    )
    parser.add_argument(
        "--check-interval",
        type=int,
        default=60,
        help="Seconds between checks (default: 60)",
    )
    parser.add_argument(
        "--max-wait",
        type=int,
        default=3600,
        help="Maximum time to wait for cleanup (default: 3600)",
    )

    # Other options
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()

    print("=" * 70)
    print("Swift Container Complete Cleanup Workflow")
    print("=" * 70)
    print()

    if args.dry_run:
        print("⚠️  DRY RUN MODE - No changes will be made")
        print()

    # Calculate delete timestamp
    if args.delete_at:
        delete_timestamp = args.delete_at
        current_time = int(time.time())
        retention_seconds = delete_timestamp - current_time
    else:
        delete_timestamp, retention_seconds = calculate_delete_timestamp(
            seconds=args.seconds,
            minutes=args.minutes,
            hours=args.hours,
            days=args.days,
            months=args.months,
        )

    duration_text = format_duration(retention_seconds)
    delete_date = datetime.fromtimestamp(delete_timestamp).strftime("%Y-%m-%d %H:%M:%S")

    print(f"Containers: {', '.join(args.containers)}")
    print(f"Retention period: {duration_text}")
    print(f"Deletion time: {delete_date} (Unix: {delete_timestamp})")

    if args.cleanup:
        print(f"Auto-cleanup: Enabled")
        print(f"Check interval: {args.check_interval} seconds")
        print(f"Max wait time: {args.max_wait} seconds")
    else:
        print(f"Auto-cleanup: Disabled (use --cleanup to enable)")

    print()

    # Connect to Swift
    print("Connecting to Swift...")
    conn = get_swift_connection()
    print("✓ Connected")

    if args.dry_run:
        print("\n⚠️  DRY RUN - Exiting without making changes")
        sys.exit(0)

    # Phase 1: Set expiration on all containers
    print(f"\n{'=' * 70}")
    print("PHASE 1: Setting Expiration on Objects")
    print("=" * 70)

    total_succeeded = 0
    total_failed = 0

    for container in args.containers:
        succeeded, failed = set_expiration_on_container(
            conn, container, delete_timestamp, args.verbose
        )
        total_succeeded += succeeded
        total_failed += failed

    print(f"\n{'=' * 70}")
    print("Phase 1 Summary")
    print("=" * 70)
    print(f"Total objects processed: {total_succeeded + total_failed}")
    print(f"Successfully set expiration: {total_succeeded}")
    if total_failed > 0:
        print(f"Failed: {total_failed}")
    print("=" * 70)

    # Phase 2: Monitor and cleanup (if enabled)
    if args.cleanup:
        print(f"\n{'=' * 70}")
        print("PHASE 2: Monitoring and Cleanup")
        print("=" * 70)
        print()
        print(f"Waiting for objects to expire and be deleted...")
        print(f"This may take a while depending on:")
        print(f"  - Expiration time: {duration_text}")
        print(f"  - Swift object-expirer interval (typically 5-15 minutes)")
        print()

        deleted = monitor_and_cleanup(
            conn,
            args.containers,
            check_interval=args.check_interval,
            max_wait=args.max_wait,
            verbose=args.verbose,
        )

        print(f"\n{'=' * 70}")
        print("Phase 2 Summary")
        print("=" * 70)
        print(f"Containers deleted: {len(deleted)}")
        for container in deleted:
            print(f"  ✓ {container}")

        remaining = set(args.containers) - set(deleted)
        if remaining:
            print(f"\nContainers not deleted: {len(remaining)}")
            for container in remaining:
                print(f"  ⏳ {container}")
        print("=" * 70)
    else:
        print(
            f"\n💡 Tip: Use --cleanup flag to automatically delete containers when empty"
        )

    print("\n✓ Workflow complete")


if __name__ == "__main__":
    main()
