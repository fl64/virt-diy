#!/bin/sh

# Configuration variables for easy customization
VM_NAME="vm"
IMAGE_URL="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
# IMAGE_PATH="/disks/image.qcow2"
IMAGE_PATH="/tmp/image.qcow2"
ISO_PATH="/tmp/cidata.iso"
QMP_SOCKET="/tmp/qmp.sock"
VM_RAM=3072
VM_VCPUS=2
VM_CPU="Nehalem"
VM_OS_VARIANT="ubuntu24.04"

# Cleanup function to handle SIGTERM and shutdown VM/services
cleanup() {
    echo "☠️ Received SIGTERM, initiating cleanup..."

    # Attempt to gracefully shut down the VM
    echo "⏳ Shutting down VM..."
    virsh shutdown $VM_NAME || echo "⚠️ Warning: Failed to issue shutdown command"

    # Wait for VM to shut down with a timeout
    timeout=20
    while [ $timeout -gt 0 ]; do
        if ! virsh list --state-running | grep -q "$VM_NAME"; then
            echo "✅ VM shutdown complete"
            break
        fi
        echo "⏳ Waiting for VM to shut down... ($timeout seconds remaining)"
        sleep 1
        timeout=$((timeout - 1))
    done

    # Force destroy VM if it doesn't shut down gracefully
    if virsh list --state-running | grep -q "$VM_NAME"; then
        echo "☠️ VM did not shut down gracefully, forcing destroy..."
        virsh destroy $VM_NAME || echo "⚠️ Warning: Failed to destroy VM"
    fi

    # Stop libvirt services
    echo "⏳ Stopping libvirt services..."
    pkill -TERM libvirtd || echo "⚠️ Warning: Failed to stop libvirtd"
    pkill -TERM virtlogd || echo "⚠️ Warning: Failed to stop virtlogd"

    # Brief pause to ensure processes terminate
    sleep 2

    echo "✅ Cleanup complete, exiting"
    exit 0
}

# Set trap to call cleanup on SIGTERM
trap cleanup SIGTERM

# Create ISO file with cloud-init configuration
echo "🛠️ Creating ISO with cloud-init"
cp -L /config/user-data /tmp/user-data
cp -L /config/meta-data /tmp/meta-data
xorriso -as mkisofs -o $ISO_PATH -V cidata -J -r /tmp/user-data /tmp/meta-data
xorriso -indev $ISO_PATH -ls

# Download VM disk image if it doesn't exist
echo "📥 Checking for disk image"
if [ ! -f $IMAGE_PATH ]; then
    echo "📥 Downloading disk image..."
    curl --progress-bar $IMAGE_URL -o $IMAGE_PATH
else
    echo "✅ Disk image already exists"
fi


# Start libvirt services
echo "🚀 Starting libvirt services"
(/usr/sbin/libvirtd 2>&1 | sed 's/^/[libvirtd] /') &
(/usr/sbin/virtlogd 2>&1 | sed 's/^/[virtlogd] /') &

echo "⏳ Waiting for libvirt to initialize..."
until virsh net-list --all > /dev/null 2>&1; do
    echo "Libvirt is not ready yet..."
    sleep 1
done
echo "Libvirt is ready."

echo "🚀 Launching VM"
virt-install \
    --name $VM_NAME \
    --os-variant $VM_OS_VARIANT \
    --ram $VM_RAM \
    --cpu $VM_CPU \
    --vcpus $VM_VCPUS \
    --disk path=$IMAGE_PATH \
    --disk path=$ISO_PATH,device=cdrom \
    --network network=default,model=virtio \
    --channel unix,source.path=/tmp/virt.sock,target.type=virtio,name=org.qemu.guest_agent.0 \
    --import \
    --graphics vnc,listen=0.0.0.0,port=5900 \
    --console pty,target_type=virtio \
    --serial pty \
    --noautoconsole \
    --virt-type kvm \
    --force

echo "👀 Monitoring VM status"
while true; do
    if virsh list --state-running | grep -q "$VM_NAME.*running"; then
        echo -n "💡 VM is running"
        if virsh qemu-agent-command $VM_NAME '{"execute":"guest-ping"}' > /dev/null 2>&1; then
            echo -n ", guest agent is working"
            virsh qemu-agent-command $VM_NAME '{"execute":"guest-get-osinfo"}' | jq -c
        else
            echo ", but guest agent is not responding"
        fi
    else
        echo "⚠️ VM is not running"
    fi
    sleep 10
done
