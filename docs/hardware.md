# Hardware

## Compute

### m715q (Proxmox) - Lenovo Thinkcentre M715q

AMD Ryzen 3 ???
???GB ??? MHz SODIMM RAM
???GB SATA SSD (Data)
???GB NVMe SSD (Boot)

### m715q2 (Proxmox) - Lenovo Thinkcentre M715q

AMD Ryzen 3 ???
???GB DDR4 ??? MHz SODIMM RAM
???GB SATA SSD (Data)
???GB NVMe SSD (Boot)

### m720q (Proxmox) - Lenovo Thinkcentre M720q

Intel Core i5 8???
32GB DDR4 ??? Mhz SODIMM RAM
500GB Samsung 870 EVO SSD (Data)
???GB NVMe SSD (Boot)

### [PLANNED] m720q2 (NixOS) - Lenovo Thinkcentre M720q

Intel Core i3 8???
16 DDR4 ??? Mhz SODIMM RAM
???GB SSD (Boot)

### m920q (Proxmox) - Lenovo Thinkcentre M720q

Intel Core i5 8???
32GB DDR4 ??? Mhz SODIMM RAM
1TB Samsung 870 EVO SSD (Data)
???GB NVMe SSD (Boot)

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
