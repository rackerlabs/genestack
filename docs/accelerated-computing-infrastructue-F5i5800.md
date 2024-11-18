# How does Rackspace implement Accelerated Computing?

![Rackspace Cloud Software](assets/images/ospc_flex_logo_red.svg){ align=left : style="max-width:175px" }

## F5 i5800

The F5 i5800 is a versatile application delivery controller (ADC) that is part of the F5 BIG-IP iSeries.
It is designed to deliver advanced traffic management, security, and application performance optimization,
making it well-suited for large enterprises, service providers, and data centers. This device provides
high performance, flexibility, and support for a range of security and application delivery functions,
ensuring consistent, secure, and optimized user experiences. Here are the key features of the F5 i5800:

  1. **High Performance and Throughput**: The i5800 offers high performance, with up to 80 Gbps of L4 throughput
     and 8 Gbps of SSL bulk encryption throughput, making it capable of handling high volumes of traffic
     and complex security requirements. Its high performance is ideal for handling large volumes of
     connections in applications that require rapid response times and high availability.

  2. **Advanced SSL/TLS Offloading**: The i5800 includes dedicated hardware for SSL/TLS offloading, which
     allows it to handle encrypted traffic with minimal impact on performance. SSL offloading enables
     faster application response times by offloading the cryptographic processing from the application
     servers, freeing up server resources and improving user experience. Supports modern encryption
     standards, including TLS 1.3, which enhances security for encrypted connections.

  3. **Comprehensive Application Security**: The F5 i5800 can be equipped with Advanced WAF (Web Application
     Firewall) capabilities to protect web applications against various threats, such as SQL injection,
     cross-site scripting (XSS), and other OWASP Top 10 vulnerabilities. It includes bot protection and
     DDoS mitigation features, safeguarding applications from automated attacks and distributed denial-of-service attacks. IP Intelligence and threat intelligence services are available to provide real-time threat
     information, helping to identify and block potentially malicious traffic.

  4. **Traffic Management with L4-L7 Capabilities**: The i5800 offers comprehensive Layer 4 to Layer 7 traffic
     management, enabling intelligent routing, load balancing, and failover capabilities. Advanced load
     balancing features, including global server load balancing (GSLB) and local traffic management
     (LTM), ensure high availability and optimal distribution of traffic across multiple servers and
     data centers. iRules scripting allows for highly customizable traffic management policies, giving
     network administrators granular control over traffic behavior and routing.

  5. **iApps and iControl for Orchestration and Automation**: iApps is F5's application-centric configuration
     framework, allowing simplified and automated deployment of application services. iControl REST
     APIs enable integration with DevOps tools and support for automation and orchestration, making
     it easier to manage complex deployments and integrate with CI/CD pipelines. These features help
     organizations streamline application deployment, increase operational efficiency, and reduce configuration
     errors.

  6. **Enhanced Security with Access Policy Manager (APM)**: The i5800 can integrate with Access Policy
     Manager (APM), which provides secure, context-based access control and authentication services.
     APM enables Single Sign-On (SSO) and multi-factor authentication (MFA) for secure access to applications,
     whether hosted on-premises or in the cloud. It also supports Zero Trust principles by verifying
     user identity and device posture, allowing for controlled access to sensitive applications.

  7. **Application Acceleration with TCP Optimization and Caching**: The i5800 provides application acceleration
     features, including TCP optimization, which improves the efficiency of TCP connections, reducing
     latency and improving application response times. It also supports caching and compression, which
     reduces the load on backend servers by storing frequently requested content and compressing responses
     for faster delivery to end-users. These features are beneficial for applications with high traffic
     demands, enhancing user experience and reducing bandwidth consumption.

  8. **Programmable and Customizable with iRules and iCall**: iRules allow administrators to customize how
     traffic is processed and managed based on specific business logic and application needs. iCall
     provides the ability to schedule tasks and execute scripts based on specific events, making it
     possible to automate responses to network and application changes. This programmability ensures
     flexibility in adapting the ADC to meet unique application requirements and security policies.

  9. **High Availability and Redundancy**: The i5800 supports active-active and active-passive high availability
     (HA) modes, ensuring continuous uptime and minimal service interruptions. With support for failover
     and synchronization across multiple units, it provides redundancy for mission-critical applications,
     enhancing reliability and resilience against failures.

  10. **Scalability and Modular Licensing**: F5's modular licensing allows organizations to add new features
      and capabilities to the i5800 as their needs evolve, including security, acceleration, and access
      features. This flexibility enables organizations to scale their ADC capabilities without needing
      to replace the hardware, providing investment protection and cost savings over time.

  11. **Virtualization Support with F5 Virtual Editions (VEs)**: The i5800 is compatible with F5's Virtual
      Editions (VEs), allowing organizations to extend their application delivery and security capabilities
      to virtual and cloud environments. With VEs, organizations can implement consistent policies across
      on-premises and cloud environments, supporting hybrid and multi-cloud strategies.

  12. **Network Integration and Compatibility**: The i5800 offers comprehensive support for various networking
      environments and can integrate with IPv6, IPsec, VLANs, and VPN configurations. It supports both
      standard and high-performance network interfaces, including 1GbE, 10GbE, and 25GbE ports, providing
      flexibility for integration into diverse network topologies. The i5800's compatibility with modern
      network protocols and interfaces ensures that it can operate effectively within complex network
      infrastructures.

In summary, the F5 i5800 is a high-performance ADC designed to optimize application delivery, provide
robust security, and enhance user experience across diverse network environments. Its features—including
SSL offloading, WAF, advanced traffic management, and programmability with iRules—make it a powerful
solution for organizations seeking to improve application performance, secure applications, and support
high traffic volumes. The i5800’s scalability, modular licensing, and cloud compatibility also make it a
future-proof choice for organizations growing their application infrastructure or adopting hybrid and
multi-cloud architectures.

### **Ideal Use Cases**

* **Large Enterprises and Data Centers**: The i5800’s high throughput and SSL offloading make it ideal for
  large organizations and data centers that require efficient traffic management and application security.

* **Service Providers**: With its comprehensive security and traffic management features, the i5800 can
  help service providers manage high traffic volumes while ensuring security and optimizing performance
  for clients.

* **E-commerce and Online Services**: The i5800’s WAF, bot protection, and DDoS mitigation features help
  protect e-commerce platforms and online services from attacks and provide a secure user experience.

* **Hybrid Cloud Environments**: The i5800’s integration with F5 VEs enables consistent application security
  and delivery across both on-premises and cloud environments, making it suitable for organizations
  adopting hybrid or multi-cloud architectures.
