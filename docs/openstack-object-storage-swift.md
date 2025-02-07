# <u>What is Openstack Swift Object Storage?</u>

Swift Object Storage is a component of the greater Openstack ecosystem.  It was one of the first core components of Openstack along side Nova in the "Austin" release.  It has been used internally by Rackspace for their Object Storage offering along with many other organizations.  It provides a scalable and durable storage solution for unstructured data such as backups, multimedia files and big data.

## <u>Why Openstack Swift Object Storage?</u>

**Scalability:** Swift is designed to handle vast amounts of data operating in a single or multi tenant environment.  Each of the core services can be scaled up and out independently of each other.  If hotspots start to happen on a single tier such as Object additional resources can be added mitigate the issue.  Each service can be broken out and scaled independently of each other depending on the use case and the data rate occurring on each tier.

**Durability**: Data placement is controlled by the operator of the cluster and Swift supports two distinctive methods of storing data.  **Replica** is the most common, fastest and least efficient means to store objects.  Replicated count is configured based on durability and environmental needs.  Swift supports Replicated copies 2-N, and can be changed gradually on a cluster if the need arises (scale out, multi region, etc).  Swift also support erasure coding support in its object storage class, powered by liberasurecode, it supports multiple K+M values to store your data.  Benefits from using erasure coded objects include higher durability in the event of a disk failure, better storage efficiency of object but at the cost of higher CPU consumption.  Swift also performs background audits on all data, ensuring that your data is retrievable, readable and unaltered.

**Total Cost of Ownership:** By combining Swift's scale up and out architecture of its services we can pinpoint hotspots in a Swift deployment and be highly prescriptive in how we tackle the issue.  Gone are the days of "throwing hardware" at the solution.  Understanding the pedigree of the data and the use case Swift can also use that same prescriptive methodology to architecting and maintaining the right durability of your data to meet your organizations needs.

## Use Cases for Swift Object

**Backup:** Most popular software backup suites can use Swift/S3 endpoint natively out of the box with little to no effort.  Swift Object can be used as the primary, secondary or offsite backup to meet the needs of your organization.  By leveraging Swift we deliver a cost effect and durable solution to your backup data.  You can also leverage multiple distinctive Swift endpoints to further separate your data and give clear distinctive regional boundaries of where your data lives at any given time.

**Archival**: By leveraging Swift CLI's, S3 CLI's, rclone or other popular GUI based Object managers such as Cyberduck you can leverage Swift for longterm storage of archival storage of your files.  If consuming a block device is more inline with your organizational needs Storage Gateways or FUSE drivers can be leveraged over changing the pipeline in your organization.   Swift helps maintain automatic deletion of files when used in conjunction with Swift Object Expirer, this will help keep costs under control by setting delete-at-dates, this can be especially useful for CCTV footage.

**Data Lakes:** Swift can serve as the underlying storage driver for data lakes.  Swift's ability to store large volumes of unstructured data makes it an ideal choice for anyone looking for a durable and cost effective storage layer for any data lake layer to manage.  Integrating your data lake application layer is as simple as consuming the Swift API or S3 API RESTful endpoint, creating containers/buckets and loading your unstructured data in to Swift.  Data lake outputs can also be stored for further refinement or consumption into another container/bucket making Swift a one stop shop for your data transformation needs.

**Artifact Storage:** Swift Object Storage can serve as a robust storage solution for managing artifacts. It can handle large binaries and files efficiently, providing scalability and durability.  Swift allows for the storage of artifacts with associated metadata, making it easier to manage different versions of artifacts and track changes.  Many CI/CD (Continuous Integration/Continuous Deployment) pipelines utilize object storage like Swift to store build artifacts. After a successful build, the artifacts can be uploaded to Swift for deployment or further testing.

# Getting Started with Swift Object Storage

Onboarding with Openstack Swift Object store is covered in the following trove of documents located here:

[Rackspace OpenStack Flex Onboarding](https://docs.rackspacecloud.com/cloud-onboarding-welcome/)

Topics include Swift CLI, S3cmd, rclone setup.

------

# **Advanced Features**


## **Object Versioning**:

Swift allows the end user to store multiple versions of the same object so you can recover from an unintended overwrite or rollback of an object to an earlier date in time.  Object versioning works with any type of content uploaded to Swift.

**Example Using `X-Versions-Location`**

1. Create a container named '*current*':

   ```
   # curl -i $publicURL/current -X PUT -H "Content-Length: 0" -H "X-Auth-Token: $token" -H "X-Versions-Location: archive"
   ```

   ```
   HTTP/1.1 201 Created
   Content-Length: 0
   Content-Type: text/html; charset=UTF-8
   X-Trans-Id: txb91810fb717347d09eec8-0052e18997
   X-Openstack-Request-Id: txb91810fb717347d09eec8-0052e18997
   Date: Thu, 23 Jan 2014 21:28:55 GMT
   ```

2. Upload an object named '*my_object*' to the '*current*' container:

```
# curl -i $publicURL/current/my_object --data-binary 1 -X PUT -H "Content-Length: 0" -H "X-Auth-Token: $token"
```

```
HTTP/1.1 201 Created
Last-Modified: Thu, 23 Jan 2014 21:31:22 GMT
Content-Length: 0
Etag: d41d8cd98f00b204e9800998ecf8427e
Content-Type: text/html; charset=UTF-8
X-Trans-Id: tx5992d536a4bd4fec973aa-0052e18a2a
X-Openstack-Request-Id: tx5992d536a4bd4fec973aa-0052e18a2a
Date: Thu, 23 Jan 2014 21:31:22 GMT
```

Nothing is written to the non-current version container when you initially **PUT** an object in the `current` container. 	However, subsequent **PUT** requests that edit an object trigger the creation of a version of that object in the `archive` container.

These non-current versions are named as follows:

```
<length><object_name>/<timestamp>
```

Where `length` is the 3-character, zero-padded hexadecimal character length of the object, `<object_name>` is 	the object name, and `<timestamp>` is the time when the object was initially created as a current version.

3. Create a second version of the Object in the '*current*' container:

```
curl -i $publicURL/current/my_object --data-binary 2 -X PUT -H "Content-Length: 0" -H "X-Auth-Token: $token"
```

```
HTTP/1.1 201 Created
Last-Modified: Thu, 23 Jan 2014 21:41:32 GMT
Content-Length: 0
Etag: d41d8cd98f00b204e9800998ecf8427e
Content-Type: text/html; charset=UTF-8
X-Trans-Id: tx468287ce4fc94eada96ec-0052e18c8c
X-Openstack-Request-Id: tx468287ce4fc94eada96ec-0052e18c8c
Date: Thu, 23 Jan 2014 21:41:32 GMT
```

4. Issue a **GET** request to the versioned object '*my_object*' to get the current version value of the object.

   List older versions of the object in the '*archive*' container:

```
# curl -i $publicURL/archive?prefix=009my_object -X GET -H "X-Auth-Token: $token"
```

```
HTTP/1.1 200 OK
Content-Length: 30
X-Container-Object-Count: 1
Accept-Ranges: bytes
X-Timestamp: 1390513280.79684
X-Container-Bytes-Used: 0
Content-Type: text/plain; charset=utf-8
X-Trans-Id: tx9a441884997542d3a5868-0052e18d8e
X-Openstack-Request-Id: tx9a441884997542d3a5868-0052e18d8e
Date: Thu, 23 Jan 2014 21:45:50 GMT

009my_object/1390512682.92052
```

!!! note

      A **POST** request to a versioned object updates only the metadata for the object and does not create a new version of the object. New versions are created only when the content of the object changes.

5. Issue a **DELETE** request to a versioned object to remove the current version of the object and replace it with the next-most current version in the non-current container.

```
# curl -i $publicURL/current/my_object -X DELETE -H "X-Auth-Token: $token"
```

```
HTTP/1.1 204 No Content
Content-Length: 0
Content-Type: text/html; charset=UTF-8
X-Trans-Id: tx006d944e02494e229b8ee-0052e18edd
X-Openstack-Request-Id: tx006d944e02494e229b8ee-0052e18edd
Date: Thu, 23 Jan 2014 21:51:25 GMT
```

List objects in the `archive` container to show that the archived object was moved back to the '*current*' container:

```
# curl -i $publicURL/archive?prefix=009my_object -X GET -H "X-Auth-Token: $token"
```

```
HTTP/1.1 204 No Content
Content-Length: 0
X-Container-Object-Count: 0
Accept-Ranges: bytes
X-Timestamp: 1390513280.79684
X-Container-Bytes-Used: 0
Content-Type: text/html; charset=UTF-8
X-Trans-Id: tx044f2a05f56f4997af737-0052e18eed
X-Openstack-Request-Id: tx044f2a05f56f4997af737-0052e18eed
Date: Thu, 23 Jan 2014 21:51:41 GMT
```

!!! note

      This next-most current version carries with it any metadata last set on it. If want to completely remove an object and you have five versions of it, you must **DELETE** it five times.

**Example Using `X-History-Location`**

1. Create '*current*' container:

```
# curl -i $publicURL/current -X PUT -H "Content-Length: 0" -H "X-Auth-Token: $token" -H "X-History-Location: archive"
```

```
HTTP/1.1 201 Created
Content-Length: 0
Content-Type: text/html; charset=UTF-8
X-Trans-Id: txb91810fb717347d09eec8-0052e18997
X-Openstack-Request-Id: txb91810fb717347d09eec8-0052e18997
Date: Thu, 23 Jan 2014 21:28:55 GMT
```

2. Upload '*my_object*' into the '*current*' container:

```
# curl -i $publicURL/current/my_object --data-binary 1 -X PUT -H "Content-Length: 0" -H "X-Auth-Token: $token"
```

```
HTTP/1.1 201 Created
Last-Modified: Thu, 23 Jan 2014 21:31:22 GMT
Content-Length: 0
Etag: d41d8cd98f00b204e9800998ecf8427e
Content-Type: text/html; charset=UTF-8
X-Trans-Id: tx5992d536a4bd4fec973aa-0052e18a2a
X-Openstack-Request-Id: tx5992d536a4bd4fec973aa-0052e18a2a
Date: Thu, 23 Jan 2014 21:31:22 GMT
```

Nothing is written to the non-current version container when you initially **PUT** an object in the '*current*' container. However, subsequent **PUT** requests that edit an object trigger the creation of a version of that object in the '*archive*' container.

These non-current versions are named as follows:

```
<length><object_name>/<timestamp>
```

Where `length` is the 3-character, zero-padded hexadecimal character length of the object, `<object_name>` is the object name, and `<timestamp>` is the time when the object was initially created as a current version.

3. Create a second version of the object in the '*current*' container:

```
# curl -i $publicURL/current/my_object --data-binary 2 -X PUT -H "Content-Length: 0" -H "X-Auth-Token: $token"
```

```
HTTP/1.1 201 Created
Last-Modified: Thu, 23 Jan 2014 21:41:32 GMT
Content-Length: 0
Etag: d41d8cd98f00b204e9800998ecf8427e
Content-Type: text/html; charset=UTF-8
X-Trans-Id: tx468287ce4fc94eada96ec-0052e18c8c
X-Openstack-Request-Id: tx468287ce4fc94eada96ec-0052e18c8c
Date: Thu, 23 Jan 2014 21:41:32 GMT
```

4. Issue a **GET** request to the versioned object '*my_object*' to get the current version value of the object.

   List older versions of the object in the '*archive*' container:

```
# curl -i $publicURL/archive?prefix=009my_object -X GET -H "X-Auth-Token: $token"
```

```
HTTP/1.1 200 OK
Content-Length: 30
X-Container-Object-Count: 1
Accept-Ranges: bytes
X-Timestamp: 1390513280.79684
X-Container-Bytes-Used: 0
Content-Type: text/plain; charset=utf-8
X-Trans-Id: tx9a441884997542d3a5868-0052e18d8e
X-Openstack-Request-Id: tx9a441884997542d3a5868-0052e18d8e
Date: Thu, 23 Jan 2014 21:45:50 GMT

009my_object/1390512682.92052
```

!!! note

      A **POST** request to a versioned object updates only the metadata for the object and does not create a new version of the object. New versions are created only when the content of the object changes.

5. Issue a **DELETE** request to a versioned object to copy the current version of the object to the archive container then delete it from the current container. Subsequent **GET** requests to the object in the current container will return `404 Not Found`.

```
# curl -i $publicURL/current/my_object -X DELETE -H "X-Auth-Token: $token"
```

```
HTTP/1.1 204 No Content
Content-Length: 0
Content-Type: text/html; charset=UTF-8
X-Trans-Id: tx006d944e02494e229b8ee-0052e18edd
X-Openstack-Request-Id: tx006d944e02494e229b8ee-0052e18edd
Date: Thu, 23 Jan 2014 21:51:25 GMT
```

List older versions of the object in the '*archive*' container:

```
# curl -i $publicURL/archive?prefix=009my_object -X GET -H "X-Auth-Token: $token"
```

```
HTTP/1.1 200 OK
Content-Length: 90
X-Container-Object-Count: 3
Accept-Ranges: bytes
X-Timestamp: 1390513280.79684
X-Container-Bytes-Used: 0
Content-Type: text/html; charset=UTF-8
X-Trans-Id: tx044f2a05f56f4997af737-0052e18eed
X-Openstack-Request-Id: tx044f2a05f56f4997af737-0052e18eed
Date: Thu, 23 Jan 2014 21:51:41 GMT

009my_object/1390512682.92052
009my_object/1390512692.23062
009my_object/1390513885.67732
```

!!! note

      In addition to the two previous versions of the object, the archive container has a “delete marker” to record when the object was deleted.
      To permanently delete a previous version, issue a **DELETE** to the version in the archive container.

**Disabling Object Versioning**

To disable object versioning for the `current` container, remove its `X-Versions-Location` metadata header by sending an empty key value.

```
# curl -i $publicURL/current -X PUT -H "Content-Length: 0" -H "X-Auth-Token: $token" -H "X-Versions-Location: "
```

```
HTTP/1.1 202 Accepted
Content-Length: 76
Content-Type: text/html; charset=UTF-8
X-Trans-Id: txe2476de217134549996d0-0052e19038
X-Openstack-Request-Id: txe2476de217134549996d0-0052e19038
Date: Thu, 23 Jan 2014 21:57:12 GMT

<html><h1>Accepted</h1><p>The request is accepted for processing.</p></html>
```

------

## **Custom Object Metadata**:

Swift allows end users the ability to tag Object metadata, this is extremely useful in identifying the source of data, notes about the object or the current processing state when the object is consumed by a data lake process.

Using the swift CLI:

```
swift upload -m ``"X-Object-Meta-Security: TopSecret" HR_files payroll_information.txt
```

Using cURL:

```
curl -X POST -H "X-Auth-Token:$TOKEN" -H 'X-Object-Meta-Security: TopSecret' $STORAGE_URL/HR_files/payroll_information.txt
```

------

## **Static Web Hosting:**

Using Swift Object you can serve static websites built in HTML to clients, this takes the need for any web servers out if your infrastructure and relies on Swift's robust infrastructure to serve web files out.

1. Make container publicly readable:

```
# swift post -r '.r:*,.rlistings' web_container
```

2. Set site index file, in this case we will use *index.html* as the index file for our site:

```
# swift post -m 'web-index:index.html' web_container
```

3. Optional: Enable file listing, this allows the container to be browsed when an *index.html* file is not specified:

```
# swift post -m 'web-listings: true' web_container
```

4. Optional: Enable CSS for file listing when site index file is not specified:

```
# swift post -m 'web-listings-css:listings.css' web_container
```

5. Set custom error pages for any visitors accessing your static website, you may specify custom 401, 404 error pages or a catch all.

```
# swift post -m 'web-error:error.html' web_container
```

!!! note

      More information on static websites can be found here:
      [Swift Create static website](https://docs.openstack.org/ocata/user-guide/cli-swift-static-website.html)

------

## **Lifecycle Management**

In OpenStack Swift, the expiration of objects can be managed using a feature called **object expiration**. This allows you to automatically delete objects after a specified period, which is useful for managing storage costs and keeping your data organized and keep in compliance with our organization data retention requirements.

There are two ways to set the object expiration, date and time based or after N seconds have passed.

Set an object to expire at an absolute time (in Unix time):

```
# swift post CONTAINER OBJECT_FILENAME -H "X-Delete-At:UNIX_TIME"
```

Set an object to expire after N seconds have passed:

```
# swift post CONTAINER OBJECT_FILENAME -H "X-Delete-After:SECONDS"
```

To check on the X-Delete-At/X-Delete-After header:

```
# swift stat CONTAINER OBJECT_FILENAME
```

To clear any X-Remove flags from an object:

```
# swift post CONTAINER OBJECT_FILENAME -H "X-Remove-Delete-At:"
```

Benefits of Object Expiration

- **Storage Management:** Helps in managing and reclaiming storage space by removing outdated or unnecessary objects.
- **Cost Efficiency:** Reduces storage costs by preventing accumulation of unneeded data.

This feature is particularly useful in scenarios like managing temporary files, logs, or any other data that has a defined lifecycle.

------

## Swift S3 REST API

S3 is a product of Amazon and AWS, Swift's S3 RESTful API is a middleware component that allows verb compatibly between a native Swift deployment and applications that only speak S3 API.  While most functionality is present in the Swift S3 middleware, some verbs are lacking or there is not a like for like feature within Swift.  For the current state of Swift and S3 verb compatibility please refer to the following upstream documentation:

[S3/Swift REST API Comparison Matrix](https://docs.openstack.org/swift/latest/s3_compat.html)

------

# **Best Practices**

## Performance:

- Keep object count under 500k per container
- Multiplex over multiple container if possible
- To increase throughput scale out the amount of API worker threads you have interacting with Swift endpoint

## Securing data:

Swift supports the optional encryption of object data at rest on storage nodes. The encryption of object data is intended to mitigate the risk of users’ data being read if an unauthorized party were to gain physical access to a disk.

!!! note

      Swift’s data-at-rest encryption accepts plaintext object data from the client, encrypts it in the cluster, and stores the encrypted data. This protects object data from inadvertently being exposed if a data drive leaves the Swift cluster. If a user wishes to ensure that the plaintext data is always encrypted while in transit and in storage, it is strongly recommended that the data be encrypted before sending it to the Swift cluster. Encrypting on the client side is the only way to ensure that the data is fully encrypted for its entire lifecycle.

The following data are encrypted while at rest in Swift:

- Object content i.e. the content of an object PUT request’s body
- The entity tag (ETag) of objects that have non-zero content
- All custom user object metadata values i.e. metadata sent using X-Object-Meta- prefixed headers with PUT or POST requests

Any data or metadata not included in the list above are not encrypted, including:

- Account, container and object names
- Account and container custom user metadata values
- All custom user metadata names
- Object Content-Type values
- Object size
- System metadata

All in-flight operations are encrypted using HTTPS and TLS encryption.

## **Cost Management**

Managing cost in Openstack Swift can be accomplished using object lifecycle management, usage monitoring and storage classes.

**Object Lifecycle Management:** Use expiration policies to automatically delete outdated or unnecessary objects, reducing the volume of stored data.

**Usage Monitoring:** Keep tabs on your Object storage spend by looking at overall container sizes for your organization, using 'swift stat container' will show you the overall usage of each container being hosted on Swift.

**Storage Classes:** Consider implementing different storage classes based on access frequency and performance needs. For example, frequently accessed data can be stored in faster, more expensive storage, while infrequently accessed data can be moved to slower, cheaper storage.  Use Swift to store archival data at lower costs, particularly for data that needs to be retained but is rarely accessed, by locking into a longer commitment on storing archival data you will save money month over month.
