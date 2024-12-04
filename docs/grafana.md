# Grafana

---

!!! note
    This deployment makes a few assumption:

    * assumes you are using OAuth using Azure
    * assumes you are using tls/ssl
    * assumes you are using ingress

    If this does not apply to your deployment adjust the overrides.yaml file and skip over any unneeded sections here

## Create secret client file

In order to avoid putting sensative information on the cli, it is recommended to create and use a secret file instead.

You can base64 encode your `client_id` and `client_secret` by using the echo and base64 command:

``` shell
echo -n "YOUR CLIENT ID OR SECRET" | base64
```

This example file is located at `/etc/genestack/kustomize/grafana/base`
example secret file:

``` yaml
apiversion: v1
data:
  client_id: base64_encoded_client_id
  client_secret: base64_encoded_client_secret
kind: secret
metadata:
  name: azure-client
  namespace: grafana
type: opaque
```

---

## Create your ssl files

If you are configuring grafana to use tls/ssl, you should create a file for your certificate and a file for your key.  After the deployment, these files can be deleted if desired since the cert and key will now be in a Kubernetes secret.

Your cert and key files should look something like the following (cert and key example taken from [VMware Docs](https://docs.vmware.com/en/VMware-NSX-Data-Center-for-vSphere/6.4/com.vmware.nsx.admin.doc/GUID-BBC4804F-AC54-4DD2-BF6B-ECD2F60083F6.html "VMware Docs")).

These example files are located in `/etc/genestack/kustomize/grafana/base`

??? example

    === "Cert file (example-cert.pem)"
        ```
        -----BEGIN CERTIFICATE-----
        MIID0DCCARIGAWIBAGIBATANBGKQHKIG9W0BAQUFADB/MQSWCQYDVQQGEWJGUJET
        MBEGA1UECAWKU29TZS1TDGF0ZTEOMAWGA1UEBWWFUGFYAXMXDTALBGNVBAOMBERP
        BWKXDTALBGNVBASMBE5TQLUXEDAOBGNVBAMMB0RPBWKGQ0EXGZAZBGKQHKIG9W0B
        CQEWDGRPBWLAZGLTAS5MCJAEFW0XNDAXMJGYMDM2NTVAFW0YNDAXMJYYMDM2NTVA
        MFSXCZAJBGNVBAYTAKZSMRMWEQYDVQQIDAPTB21LLVN0YXRLMSEWHWYDVQQKDBHJ
        BNRLCM5LDCBXAWRNAXRZIFB0ESBMDGQXFDASBGNVBAMMC3D3DY5KAW1PLMZYMIIB
        IJANBGKQHKIG9W0BAQEFAAOCAQ8AMIIBCGKCAQEAVPNAPKLIKDVX98KW68LZ8PGA
        RRCYERSNGQPJPIFMVJJE8LUCOXGPU0HEPNNTUJPSHBNYNKCVRTWHN+HAKBSP+QWX
        SXITRW99HBFAL1MDQYWCUKOEB9CW6INCTVUN4IRVKN9T8E6Q174RBCNWA/7YTC7P
        1NCVW+6B/AAN9L1G2PQXGRDYC/+G6O1IZEHTWHQZE97NY5QKNUUVD0V09DC5CDYB
        AKJQETWWV6DFK/GRDOSED/6BW+20Z0QSHPA3YNW6QSP+X5PYYMDRZRIR03OS6DAU
        ZKCHSRYC/WHVURX6O85D6QPZYWO8XWNALZHXTQPGCIA5SU9ZIYTV9LH2E+LSWWID
        AQABO3SWETAJBGNVHRMEAJAAMCWGCWCGSAGG+EIBDQQFFH1PCGVUU1NMIEDLBMVY
        YXRLZCBDZXJ0AWZPY2F0ZTADBGNVHQ4EFGQU+TUGFTYN+CXE1WXUQEA7X+YS3BGW
        HWYDVR0JBBGWFOAUHMWQKBBRGP87HXFVWGPNLGGVR64WDQYJKOZIHVCNAQEFBQAD
        GGEBAIEEMQQHEZEXZ4CKHE5UM9VCKZKJ5IV9TFS/A9CCQUEPZPLT7YVMEVBFNOC0
        +1ZYR4TXGI4+5MHGZHYCIVVHO4HKQYM+J+O5MWQINF1QOAHUO7CLD3WNA1SKCVUV
        VEPIXC/1AHZRG+DPEEHT0MDFFOW13YDUC2FH6AQEDCEL4AV5PXQ2EYR8HR4ZKBC1
        FBTUQUSVA8NWSIYZQ16FYGVE+ANF6VXVUIZYVWDRPRV/KFVLNA3ZPNLMMXU98MVH
        PXY3PKB8++6U4Y3VDK2NI2WYYLILS8YQBM4327IKMKDC2TIMS8U60CT47MKU7ADY
        CBTV5RDKRLAYWM5YQLTIGLVCV7O=
        -----END CERTIFICATE-----
        ```

    === "Key file (example-key.pem)"
        ```
        -----BEGIN RSA PRIVATE KEY-----
        MIIEOWIBAAKCAQEAVPNAPKLIKDVX98KW68LZ8PGARRCYERSNGQPJPIFMVJJE8LUC
        OXGPU0HEPNNTUJPSHBNYNKCVRTWHN+HAKBSP+QWXSXITRW99HBFAL1MDQYWCUKOE
        B9CW6INCTVUN4IRVKN9T8E6Q174RBCNWA/7YTC7P1NCVW+6B/AAN9L1G2PQXGRDY
        C/+G6O1IZEHTWHQZE97NY5QKNUUVD0V09DC5CDYBAKJQETWWV6DFK/GRDOSED/6B
        W+20Z0QSHPA3YNW6QSP+X5PYYMDRZRIR03OS6DAUZKCHSRYC/WHVURX6O85D6QPZ
        YWO8XWNALZHXTQPGCIA5SU9ZIYTV9LH2E+LSWWIDAQABAOIBAFML8CD9A5PMQLW3
        F9BTTQZ1SRL4FVP7CMHSXHVJSJEHWHHCKEE0OBKWTRSGKTSM1XLU5W8IITNHN0+1
        INR+78EB+RRGNGDAXH8DIODKEY+8/CEE8TFI3JYUTKDRLXMBWIKSOUVVIUMOQ3FX
        OGQYWQ0Z2L/PVCWY/Y82FFQ3YSC5GAJSBBYSCRG14BQO44ULRELE4SDWS5HCJKYB
        EI2B8COMUCQZSOTXG9NILN/JE2BO/I2HGSAWIBGCODBMS8K6TVSSRZMR3KJ5O6J+
        77LGWKH37BRVGBVYVBQ6NWPL0XLG7DUV+7LWEO5QQAPY6AXB/ZBCKQLQU6/EJOVE
        YDG5JQECGYEA9KKFTZD/WEVAREA0DZFEJRU8VLNWOAGL7CJAODXQXOS4MCR5MPDT
        KBWGFKLFFH/AYUNPBLK6BCJP1XK67B13ETUA3I9Q5T1WUZEOBIKKBLFM9DDQJT43
        UKZWJXBKFGSVFRYPTGZST719MZVCPCT2CZPJEGN3HLPT6FYW3EORNOECGYEAXIOU
        JWXCOMUGAB7+OW2TR0PGEZBVVLEGDKAJ6TC/HOKM1A8R2U4HLTEJJCRLLTFW++4I
        DDHE2DLER4Q7O58SFLPHWGPMLDEZN7WRLGR7VYFUV7VMAHJGUC3GV9AGNHWDLA2Q
        GBG9/R9OVFL0DC7CGJGLEUTITCYC31BGT3YHV0MCGYEA4K3DG4L+RN4PXDPHVK9I
        PA1JXAJHEIFEHNAW1D3VWKBSKVJMGVF+9U5VEV+OWRHN1QZPZV4SURI6M/8LK8RA
        GR4UNM4AQK4K/QKY4G05LKRIK9EV2CGQSLQDRA7CJQ+JN3NB50QG6HFNFPAFN+J7
        7JUWLN08WFYV4ATPDD+9XQECGYBXIZKZFL+9IQKFOCONVWAZGO+DQ1N0L3J4ITIK
        W56CKWXYJ88D4QB4EUU3YJ4UB4S9MIAW/ELEWKZIBWPUPFAN0DB7I6H3ZMP5ZL8Q
        QS3NQCB9DULMU2/TU641ERUKAMIOKA1G9SNDKAZUWO+O6FDKIB1RGOBK9XNN8R4R
        PSV+AQKBGB+CICEXR30VYCV5BNZN9EFLIXNKAEMJURYCXCRQNVRNUIUBVAO8+JAE
        CDLYGS5RTGOLZIB0IVERQWSP3EI1ACGULTS0VQ9GFLQGAN1SAMS40C9KVNS1MLDU
        LHIHYPJ8USCVT5SNWO2N+M+6ANH5TPWDQNEK6ZILH4TRBUZAIHGB
        -----END RSA PRIVATE KEY-----
        ```

---

## Update datasources.yaml

The datasource.yaml file is located at `/etc/genestack/kustomize/grafana/base`

If you have specific datasources that should be populated when grafana deploys, update the datasource.yaml to use your values.  The example below shows one way to configure prometheus and loki datasources.

example datasources.yaml file:

``` yaml
datasources:
  datasources.yaml:
    apiversion: 1
    datasources:
    - name: prometheus
      type: prometheus
      access: proxy
      url: http://kube-prometheus-stack-prometheus.prometheus.svc.cluster.local:9090
      isdefault: true
    - name: loki
      type: loki
      access: proxy
      url: http://loki-gateway.{{ $.Release.Namespace }}.svc.cluster.local:80
      editable: false
```

---

## Update grafana-values.yaml

The grafana-values.yaml file is located at `/etc/genestack/kustomize/grafana/base`

You must edit this file to include your specific url and azure tenant id

---

## Create the tls secret and install

``` shell
kubectl -n grafana create secret tls grafana-tls-public --cert=/etc/genestack/kustomize/grafana/base/cert.pem --key=/etc/genestack/kustomize/grafana/base/key.pem

kubectl kustomize --enable-helm /etc/genestack/kustomize/grafana/overlay | \
  kubectl -n grafana apply -f -
```
