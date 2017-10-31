#!/usr/bin/sh

set -xeuo pipefail

output_dir="/home/output/"
base_dir="$(pwd)"
mkdir -p $base_dir/logs

# Start libvirtd
mkdir -p /var/run/libvirt
libvirtd &
sleep 5
virtlogd &

pushd ${output_dir}/ostree
python -m SimpleHTTPServer &
popd

chmod 666 /dev/kvm

function clean_up {
  set +e
  pushd ${output_dir}/images
  ln -sf $(ls -tr fedora-atomic-*.qcow2 | tail -n 1) untested-atomic.qcow2
  popd
  kill $(jobs -p)
  for screenshot in /var/lib/oz/screenshots/*.ppm; do
      [ -e "$screenshot" ] && cp $screenshot ${base_dir}/logs
  done
}
trap clean_up EXIT SIGHUP SIGINT SIGTERM

{ #group for tee

# A simple shell script to automate v2c converstion
# using Image Factory in a container

# argument 1: Path to file containing the image to be converted

# Factory defaults to wanting a root PW in the TDL - this causes
# problems with converted images - just force it
# TODO: Point the working directories at the bind mounted location?

# Do our thing
if [ "${branch}" = "rawhide" ]; then
    VERSION="rawhide"
else
    VERSION=$(echo $branch | sed -e 's/[a-zA-Z]*//')
fi

REF="fedora/${branch}/x86_64/atomic-host"

touch ${base_dir}/logs/ostree.props

imgdir=/var/lib/imagefactory/storage/

#version=$(ostree --repo=${output_dir}/ostree show --print-metadata-key=version $REF| sed -e "s/'//g")
#release=$(ostree --repo=${output_dir}/ostree rev-parse $REF| cut -c -15)

if [ -d "${output_dir}/images" ]; then
    for image in ${output_dir}/images/fedora-atomic-*.qcow2; do
        if [ -e "$image" ]; then
            # Find the last image we pushed
            prev_img=$(ls -tr ${output_dir}/images/fedora-atomic-*.qcow2 | tail -n 1)
            prev_rel=$(echo $prev_img | sed -e 's/.*-\([^-]*\).qcow2/\1/')
            # Don't fail if the previous build has been pruned
            (rpm-ostree db --repo=${output_dir}/ostree diff $prev_rel $ostree_shortsha || echo "Previous build has been pruned") | tee ${base_dir}/logs/packages.txt
        fi
        break
    done
else
    mkdir ${output_dir}/images
fi

# Grab the kickstart file from fedora upstream
curl -o ${base_dir}/logs/fedora-atomic.ks https://pagure.io/fedora-kickstarts/raw/${branch}/f/fedora-atomic.ks

# Put new url into the kickstart file
sed -i "s|^ostreesetup.*|ostreesetup --nogpg --osname=fedora-atomic --remote=fedora-atomic --url=http://192.168.124.1:8000/ --ref=$REF|" ${base_dir}/logs/fedora-atomic.ks

# point to upstream
sed -i "s|\(%end.*$\)|ostree remote delete fedora-atomic\nostree remote add --set=gpg-verify=false fedora-atomic ${HTTP_BASE}/${branch}/ostree\n\1|" ${base_dir}/logs/fedora-atomic.ks

# Remove ostree refs create form upstream kickstart
sed -i "s|^ostree refs.*||" ${base_dir}/logs/fedora-atomic.ks
sed -i "s|^ostree admin set-origin.*||" ${base_dir}/logs/fedora-atomic.ks

# Pull down Fedora net install image if needed
if [ ! -e "${output_dir}/netinst" ]; then
    mkdir -p ${output_dir}/netinst
fi

pushd ${output_dir}/netinst
# First try and download iso from development
wget -c -r -nd -A iso --accept-regex "Fedora-Everything-netinst-.*\.iso" "http://dl.fedoraproject.org/pub/fedora/linux/development/${VERSION}/Everything/x86_64/iso/" || true
# If unable to download from development then try downloading from releases
wget -c -r -nd -A iso --accept-regex "Fedora-Everything-netinst-.*\.iso" "http://dl.fedoraproject.org/pub/fedora/linux/releases/${VERSION}/Everything/x86_64/iso/" || true

latest=$(ls --hide Fedora-Everything-netinst-x86_64.iso | tail -n 1)
if [ -n "$latest" ]; then
    ln -sf $latest Fedora-Everything-netinst-x86_64.iso
fi
popd

# Create a tdl file for imagefactory
#       <install type='url'>
#           <url>http://download.fedoraproject.org/pub/fedora/linux/releases/25/Everything/x86_64/os/</url>
#       </install>
cat <<EOF >${base_dir}/logs/fedora-${branch}.tdl
<template>
    <name>${branch}</name>
    <os>
        <name>Fedora</name>
        <version>${VERSION}</version>
        <arch>x86_64</arch>
        <install type='iso'>
            <iso>file://${output_dir}/netinst/Fedora-Everything-netinst-x86_64.iso</iso>
        </install>
        <rootpw>password</rootpw>
        <kernelparam>console=ttyS0</kernelparam>
    </os>
</template>
EOF

#export LIBGUESTFS_BACKEND=direct

imagefactory --debug --imgdir $imgdir --timeout 3000 base_image ${base_dir}/logs/fedora-${branch}.tdl --parameter offline_icicle true --file-parameter install_script ${base_dir}/logs/fedora-atomic.ks

# convert to qcow
#imgname="fedora-atomic-$version-$ostree_shortsha"
qemu-img convert -c -p -O qcow2 $imgdir/*body ${output_dir}/images/$imgname.qcow2

# Record the commit so we can test it later
commit=$(ostree --repo=${output_dir}/ostree rev-parse ${REF})
cat << EOF > ${base_dir}/logs/ostree.props
builtcommit=$commit
image2boot=${HTTP_BASE}/${branch}/images/$imgname.qcow2
image_name=$imgname.qcow2
EOF

# Cleanup older qcow2 images
pushd ${output_dir}/images || exit 1
latest=""
if [ -e "latest-atomic.qcow2" ]; then
    latest=$(readlink latest-atomic.qcow2)
fi

# delete images over 3 days old but don't delete what our latest link points to
find . -type f -mtime +3 ! -name "$latest" -exec rm -v {} \;
popd

} 2>&1 | tee ${base_dir}/logs/console.log #group for tee
