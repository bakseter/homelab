# Hardware

## Compute

### m720q2 (NixOS) - Lenovo Thinkcentre M720q

Intel Core i3-8100T
16 DDR4 2667 Mhz SODIMM RAM
120GB SSD (Boot)

### m715q (Proxmox) - Lenovo Thinkcentre M715q

AMD Ryzen 3 PRO 2200GE (4 cores)
32GB DDR4 3200MHz SODIMM RAM
256GB NVMe SSD (Boot)
500GB SATA SSD (Data)

### m715q2 (Proxmox) - Lenovo Thinkcentre M715q

AMD Ryzen 3 PRO 2200GE (4 cores)
16GB DDR4 2666MHz SODIMM RAM
256GB NVMe SSD (Boot)
128GB SATA SSD (Data)

### m720q (Proxmox) - Lenovo Thinkcentre M720q

Intel Core i5-8400T (6 cores)
32GB DDR4 3200Mhz SODIMM RAM
256GB NVMe SSD (Boot)
500GB Samsung 870 EVO SSD (Data)

### m920q (Proxmox) - Lenovo Thinkcentre M920q

Intel Core i5-8500T (6 cores)
32GB DDR4 2667Mhz SODIMM RAM
256GB NVMe SSD (Boot)
1TB Samsung 870 EVO SSD (Data)

## Networking

### Telia C1 Smart Router

Used only as modem, set to "bridge mode".

### Mikrotik hAP ax3

Main router, connected to modem.

### Mikrotik hAP ax S

Connected to main router via ethernet (soon fiber), used as WiFi extender.

### TP-Link SG108E

Managed switch, connected to main router via ethernet.
Used as dedicated switch for Proxmox/Talos cluster.
