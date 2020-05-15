using System;
using System.Linq;
using System.Collections.Generic;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using Cassandra;

namespace cassandra_c_
{
    class Program
    {
        static string service = "HOST.aivencloud.com";
        static string caPath = @".\ca.pem";
        static int port = 18787;
        
        static void Main(string[] args)
        {
            var certificateValidator = new CustomRootCaCertificateValidator(new X509Certificate2(Program.caPath));
            var hostMap = new List<(string ip, string hostname)>();
            string[] cp = { Program.service };
            foreach (var host in cp)
            {
                hostMap.AddRange(Dns.GetHostAddresses(host).Select(ip => (ip.ToString(), host)));
            }
            
            var cluster = Cluster.Builder()
            .AddContactPoint(service)
            .WithPort(Program.port)
            .WithSSL(new SSLOptions()
            .SetHostNameResolver(ipAdd =>
            {
                // https://datastax-oss.atlassian.net/browse/CSHARP-652?page=com.atlassian.jira.plugin.system.issuetabpanels%3Aall-tabpanel
                var ip = ipAdd.ToString();
                foreach (var host in hostMap.Where(_ => _.ip == ip))
                {
                    return host.hostname;
                }
                return ip;
            })
            .SetCertificateCollection(new X509Certificate2Collection
            {
                new X509Certificate2(Program.caPath),
            })
            .SetRemoteCertValidationCallback(
                (
                    sender, certificate, chain, errors) => certificateValidator.Validate(certificate, chain, errors)
                )
            )
            .WithCredentials("USER", "PWD")
            .Build();
            cluster.Connect();
        }
    }

    // https://docs.datastax.com/en/developer/csharp-driver/3.12/features/tls/
    class CustomRootCaCertificateValidator
    {
        private readonly X509Certificate2 _trustedRootCertificateAuthority;

        public CustomRootCaCertificateValidator(X509Certificate2 trustedRootCertificateAuthority)
        {
            _trustedRootCertificateAuthority = trustedRootCertificateAuthority;
        }

        public bool Validate(X509Certificate cert, X509Chain chain, SslPolicyErrors errors)
        {
            if (errors == SslPolicyErrors.None)
            {
                return true;
            }

            if ((errors & SslPolicyErrors.RemoteCertificateNotAvailable) != 0)
            {
                Console.WriteLine("SSL validation failed due to SslPolicyErrors.RemoteCertificateNotAvailable.");
                return false;
            }

            if ((errors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0)
            {
                Console.WriteLine("SSL validation failed due to SslPolicyErrors.RemoteCertificateNameMismatch.");
                // set to true when you do not use SetHostNameResolver
                return false;
            }

            if ((errors & SslPolicyErrors.RemoteCertificateChainErrors) != 0)
            {
                // verify if the chain is correct
                foreach (var status in chain.ChainStatus)
                {
                    if (status.Status != X509ChainStatusFlags.NoError ||
                        status.Status != X509ChainStatusFlags.UntrustedRoot)
                    {
                        Console.WriteLine(
                            "Certificate chain validation failed. Found chain status {0} ({1}).", status.Status,
                            status.StatusInformation);
                        return false;
                    }
                }

                //Now that we have tested to see if the cert builds properly, we now will check if the thumbprint
                //of the root ca matches our trusted one
                var rootCertThumbprint = chain.ChainElements[chain.ChainElements.Count - 1].Certificate.Thumbprint;
                if (rootCertThumbprint != _trustedRootCertificateAuthority.Thumbprint)
                {
                    Console.WriteLine(
                        "Root certificate thumbprint mismatch. Expected {0} but found {1}.",
                        _trustedRootCertificateAuthority.Thumbprint, rootCertThumbprint);
                    return false;
                }
            }

            return true;
        }
    }
}
