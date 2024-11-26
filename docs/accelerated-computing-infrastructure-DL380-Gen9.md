# How does Rackspace implement Accelerated Computing?

![Rackspace Cloud Software](assets/images/ospc_flex_logo_red.svg){ align=left : style="max-width:175px" }

## HPE ProLiant DL380 Gen9

The HPE ProLiant DL380 Gen9 is a versatile and reliable server designed to handle a wide variety of
workloads in data centers, ranging from traditional business applications to virtualized environments
and data-intensive tasks. Here are the key features of the DL380 Gen9:

  1. **Scalability and Performance**:
     * **Dual-Socket Support**: The DL380 Gen9 supports two Intel Xeon E5-2600 v3 or v4 series processors,
       offering up to 44 cores per server (22 cores per processor) for significant multi-threaded performance.

     * **High Memory Capacity**: With 24 DIMM slots, the server supports up to 3 TB of DDR4 RAM (when using
       128 GB LRDIMMs), providing ample memory for memory-intensive applications and virtualized environments.

     * **Enhanced Compute Power**: The Intel Xeon E5-2600 v3/v4 processors provide improved power efficiency
       and processing power, making the DL380 Gen9 suitable for modern enterprise workloads.

  2. Flexible Storage Options:
     * **Up to 24 SFF (Small Form Factor) Drives or 12 LFF (Large Form Factor) Drives**: The DL380 Gen9 can
       accommodate a variety of storage configurations, including a mix of SAS, SATA, and NVMe drives.
       This flexibility allows for a mix of high-performance storage (e.g., SSDs) and high-capacity
       storage (e.g., HDDs).

     * **Support for NVMe SSDs**: NVMe support enables faster storage performance, which is crucial for
       workloads that require high-speed I/O, such as database applications and analytics.

     * **HPE Smart Array Controllers**: Integrated with HPE’s Smart Array controllers, the DL380 Gen9 offers
       advanced storage management, data protection, and RAID functionality for improved performance and
       data redundancy.

  3. High Availability and Redundancy:
     * **Redundant Power Supplies**: The DL380 Gen9 supports hot-swappable, redundant power supplies, which
       provide continuous operation in the event of a power supply failure, enhancing uptime.

     * **Hot-Plug Fans and Drives**: It includes hot-pluggable fans and drive bays, allowing for hardware
       maintenance without downtime, which is essential for mission-critical applications.

     * **RAID Support**: The HPE Smart Array controllers provide RAID support to enhance data redundancy
       and improve fault tolerance, with options for RAID 0, 1, 5, 6, 10, 50, and 60.

  4. **Networking and Expansion Capabilities**:
     * **Embedded 4 x 1GbE Ports**: The DL380 Gen9 comes with four embedded 1 GbE ports, providing network
       connectivity for standard workloads.

     * **FlexibleLOM (FlexibleLAN on Motherboard)**: The FlexibleLOM slot allows users to customize their
       networking configuration, including options for 10 GbE and 25 GbE network adapters.

     * **Multiple PCIe Slots**: With up to 6 PCIe 3.0 slots, the server allows for significant expansion,
       including support for additional NICs, HBAs, and GPUs, giving flexibility for future upgrades
       and integration with storage and network infrastructure.

  5. **GPU Support for Acceleration**: The DL380 Gen9 supports GPU accelerators for compute-intensive applications,
     including NVIDIA GPUs, making it suitable for machine learning, AI, and high-performance computing
     (HPC) workloads. This capability enables the DL380 Gen9 to handle workloads that require massive
     parallel processing, such as scientific simulations, engineering modeling, and deep learning.

  6. **Advanced Management with HPE iLO 4**: HPE Integrated Lights-Out (iLO 4) provides comprehensive remote
     management and monitoring, allowing administrators to manage and troubleshoot the server remotely.
     Intelligent Provisioning and Active Health System: Built-in tools like Intelligent Provisioning
     simplify server deployment, while the Active Health System continuously monitors the server’s health
     and logs system events for proactive management. Remote Console and Virtual Media: iLO offers a
     graphical remote console and virtual media support, which streamlines maintenance and reduces the
     need for physical access.

  7. Advanced Security Features:
     * **Secure Boot and Firmware Validation**: The DL380 Gen9 includes secure boot and runtime firmware
       validation to protect against firmware-level attacks.

     * **TPM (Trusted Platform Module) Support**: The DL380 Gen9 supports TPM 1.2 and 2.0, providing enhanced
     hardware-based security for encryption and key storage.

     * **Lockable Drive Bays**: Physical security is enhanced with lockable drive bays, reducing the risk
       of unauthorized physical access to the storage drives.

  8. Energy Efficiency:
     * **HPE Power Supplies with 80 PLUS Platinum and Titanium Efficiency**: These high-efficiency power
       supplies help reduce power consumption and overall energy costs, which is essential for data
       centers aiming to minimize their carbon footprint.

     * **HPE Power Regulator and Dynamic Power Capping**: HPE’s power management tools allow the DL380 Gen9
       to optimize power usage dynamically, saving energy based on workload requirements.

  9. **Operating System and Hypervisor Support**: The DL380 Gen9 is compatible with a wide range of operating
     systems, including Microsoft Windows Server, Red Hat Enterprise Linux, SUSE Linux Enterprise Server,
     Ubuntu, VMware ESXi, and others. This broad compatibility makes it a suitable choice for diverse
     environments, supporting both physical and virtualized deployments with ease.

  10. **Modular Design for Flexibility**:
      * **Tool-Free Access**: The DL380 Gen9 has a tool-free design, allowing for easy upgrades and maintenance,
        which reduces downtime and operational complexity.

      * **Optional Optical Drive Bay**: The server provides an option for an optical drive bay, which can
        be useful for software installations and backups in environments that still rely on physical media.

In summary, the HPE ProLiant DL380 Gen9 is a powerful, versatile, and energy-efficient server well-suited
for a range of enterprise applications, from general-purpose tasks to demanding workloads like virtualization,
database management, and compute-heavy analytics. With support for dual CPUs, high memory capacity,
flexible storage options, and GPU acceleration, it provides the performance and scalability required
for modern data center needs. Its advanced management, security, and power efficiency features make it
an excellent choice for organizations seeking a balance of performance, reliability, and operational simplicity.

### **Ideal Use Cases**

* **Virtualization and Cloud Infrastructure**: Organizations looking to reduce physical server sprawl, increase
  resource utilization, and improve flexibility in workload management.

* **Database and Analytics Workloads**: Enterprises that need reliable, high-performance database servers
  for online transaction processing (OLTP), data warehousing, or big data analytics.

* **High-Performance Computing (HPC) and Scientific Applications**: Research institutions, universities,
  and engineering firms needing a scalable platform to perform computationally demanding tasks.

* **Application Hosting and Web Services**: Small to large enterprises that require a stable and powerful
  platform for hosting diverse business applications and web services.

* **Backup and Disaster Recovery Solutions**: Organizations looking for a dependable backup solution or
  a disaster recovery server to protect critical data and ensure business continuity.

* **Software-Defined Storage (SDS)**: Enterprises looking to implement a flexible, scalable storage solution
  without investing in dedicated storage hardware.

* **Hyperconverged Infrastructure (HCI)**: Businesses that want a unified infrastructure solution to simplify
  management, reduce costs, and improve scalability.

* **Edge Computing and Remote Office Deployments**: Enterprises needing processing capabilities at remote
  sites or branch offices without compromising on performance and reliability.

* **Enterprise File and Print Services**: Organizations needing centralized, high-availability file storage
  and print management.

* **Development and Testing Environments**: Development teams that need dedicated resources for software
  testing, application development, and quality assurance activities.

* **Security Applications (Firewall, IDS/IPS)**: Enterprises implementing network security solutions in-house,
  especially in regulated industries or organizations with stringent security requirements.

* **Email and Collaboration Platforms**: Organizations that host on-premises email and collaboration systems
  for security, compliance, or operational preferences.
