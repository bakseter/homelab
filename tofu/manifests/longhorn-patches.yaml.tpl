machine:
  disks:
    - device: /dev/sdb
      partitions:
        - mountpoint: /var/lib/longhorn
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
  %{~ if length(extension_image_refs) > 0 ~}
  install:
    extensions:
    %{~ for image_ref in extension_image_refs ~}
      - image: ${image_ref}
    %{~ endfor ~}
  %{~ endif ~}
