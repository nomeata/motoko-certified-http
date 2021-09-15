/*
This small Motoko canister demonstrates, as a proof of concept, how to serve
HTTP requests with dynamic data, and how to do that in a certified way.

To learn more about the theory behind certified variables, I recommend
my talk at https://dfinity.org/howitworks/response-certification
*/


/*
We start with s bunch of imports.
*/

import T "mo:base/Text";
import O "mo:base/Option";
import A "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Iter "mo:base/Iter";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import CertifiedData "mo:base/CertifiedData";
import SHA256 "mo:sha256/SHA256";


/*
The actor functionality is pretty straight forward: We store
a string, provide an update call to set it, and we define a function
that includes that string in the main page of our service.
*/

actor Self {
  stable var last_message : Text = "Nobody said anything yet.";

  public shared func leave_message(msg : Text) : async () {
    last_message := msg;
    update_asset_hash(); // will be explained below
  };

  func my_id(): Principal = Principal.fromActor(Self);

  func main_page(): Blob {
    return T.encodeUtf8 (
      "This canister demonstrates certified HTTP assets from Motoko.\n" #
      "\n" #
      "You can see this text at https://" # debug_show my_id() # ".ic0.app/\n" #
      "(note, no raw!) and it will validate!\n" #
      "\n" #
      "And to demonstrate that this really is dynamic, you can leave a" #
      "message at https://ic.rocks/principal/" # debug_show my_id() # "\n" #
      "\n" #
      "The last message submitted was:\n" #
      last_message
    )
  };


/*
To serve HTTP assets, we have to define a query method called `http_request`,
and return the body and the headers. If you don’t care about certification and
just want to serve from <canisterid>.raw.ic0.app, you can do that without
worrying about the ic-certification header.
*/

  type HeaderField = (Text, Text);

  type HttpResponse = {
    status_code: Nat16;
    headers: [HeaderField];
    body: Blob;
  };

  type HttpRequest  = {
    method: Text;
    url: Text;
    headers: [HeaderField];
    body: Blob;
  };

  public query func http_request(req : HttpRequest) : async HttpResponse {
    // check if / is requested
    if ((req.method, req.url) == ("GET", "/")) {
      // If so, return the main page with with right headers
      return {
        status_code = 200;
        headers = [ ("content-type", "text/plain"), certification_header() ];
        body = main_page()
      }
    } else {
      // Else return an error code. Note that we cannot certify this response
      // so a user going to https://ce7vw-haaaa-aaaai-aanva-cai.ic0.app/foo
      // will not see the error message
      return {
        status_code = 404;
        headers = [ ("content-type", "text/plain") ];
        body = "404 Not found.\n This canister only serves /.\n"
      }
    }
  };

/*
If it weren’t for certification, this would be it. The remainder of the file deals with certification.
*/

/*
To certify HTTP assets, we have to put them into a hash tree. The data structure for hash trees
can be defined as follows, straight from
https://sdk.dfinity.org/docs/interface-spec/index.html#_certificate
*/

  type Hash = Blob;
  type Key = Blob;
  type Value = Blob;
  type HashTree = {
    #empty;
    #pruned : Hash;
    #fork : (HashTree, HashTree);
    #labeled : (Key, HashTree);
    #leaf : Value;
  };

/*
The (undocumented) interface for certified assets requires the service to put
all HTTP resources into such a tree. We only have one resource, so that is simple:
*/

  func asset_tree() : HashTree {
    #labeled ("http_assets",
      #labeled ("/",
        #leaf (h(main_page()))
      )
    );
  };

/*
We use this tree twice. In update calls that can change the assets, we have to
take the root hash of that tree and pass it to the system:
*/

  func update_asset_hash() {
    CertifiedData.set(hash_tree(asset_tree()));
  };

/*
We should also do this after upgrades:
*/
  system func postupgrade() {
    update_asset_hash();
  };

/*
In fact, we should do it during initialization as well, but Motoko’s definedness analysis is
too strict and will not allow the following, and there is no `system func init` in Motoko:
*/
  // update_asset_hash();

/*
The other use of the tree is when calculating the ic-certificate header. This header
contains the certificate obtained from the system, which we just pass through,
and our hash tree. There is CBOR and Base64 encoding involved here.
*/

  func certification_header() : HeaderField {
    let cert = switch (CertifiedData.getCertificate()) {
      case (?c) c;
      case null {
        // unfortunately, we cannot do
        //   throw Error.reject("getCertificate failed. Call this as a query call!")
        // here, because this function isn’t async, but we can’t make it async
        // because it is called from a query (and it would do the wrong thing) :-(
        //
        // So just return erronous data instead
        "getCertificate failed. Call this as a query call!" : Blob
      }
    };
    return
      ("ic-certificate",
        "certificate=:" # base64(cert) # ":, " #
        "tree=:" # base64(cbor_tree(asset_tree())) # ":"
      )
  };

/*
(Note that a more serious implementatin would not return the full tree here, but prune
any branches of the tree not relevant for the requested resource.)
*/

/*
That’s it! The rest is generic code that ought to be libraries, but wasn’t too bad
to write by hand either. The code below has hopefully reasonable performance
characteristics, even though they are not highly optimzed.
*/

/*
Helpers for hashing one, two or three blobs:
These can hopefully be simplified once https://github.com/dfinity-lab/motoko/issues/966 is resolved.
*/

  func h(b1 : Blob) : Blob {
    let d = SHA256.Digest();
    d.write(Blob.toArray(b1));
    Blob.fromArray(d.sum());
  };
  func h2(b1 : Blob, b2 : Blob) : Blob {
    let d = SHA256.Digest();
    d.write(Blob.toArray(b1));
    d.write(Blob.toArray(b2));
    Blob.fromArray(d.sum());
  };
  func h3(b1 : Blob, b2 : Blob, b3 : Blob) : Blob {
    let d = SHA256.Digest();
    d.write(Blob.toArray(b1));
    d.write(Blob.toArray(b2));
    d.write(Blob.toArray(b3));
    Blob.fromArray(d.sum());
  };

/*
Base64 encoding.
*/

  func base64(b : Blob) : Text {
    let base64_chars : [Text] = ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z","0","1","2","3","4","5","6","7","8","9","+","/"];
    let bytes = Blob.toArray(b);
    let pad_len = if (bytes.size() % 3 == 0) { 0 } else {3 - bytes.size() % 3 : Nat};
    let padded_bytes = A.append(bytes, A.tabulate<Nat8>(pad_len, func(_) { 0 }));
    var out = "";
    for (j in Iter.range(1,padded_bytes.size() / 3)) {
      let i = j - 1 : Nat; // annoying inclusive upper bound in Iter.range
      let b1 = padded_bytes[3*i];
      let b2 = padded_bytes[3*i+1];
      let b3 = padded_bytes[3*i+2];
      let c1 = (b1 >> 2          ) & 63;
      let c2 = (b1 << 4 | b2 >> 4) & 63;
      let c3 = (b2 << 2 | b3 >> 6) & 63;
      let c4 = (b3               ) & 63;
      out #= base64_chars[Nat8.toNat(c1)]
          # base64_chars[Nat8.toNat(c2)]
          # (if (3*i+1 >= bytes.size()) { "=" } else { base64_chars[Nat8.toNat(c3)] })
          # (if (3*i+2 >= bytes.size()) { "=" } else { base64_chars[Nat8.toNat(c4)] });
    };
    return out
  };


/*
The root hash of a HashTree. This is the algorithm `reconstruct` described in
https://sdk.dfinity.org/docs/interface-spec/index.html#_certificate
*/

  func hash_tree(t : HashTree) : Hash {
    switch (t) {
      case (#empty) {
        h("\11ic-hashtree-empty");
      };
      case (#fork(t1,t2)) {
        h3("\10ic-hashtree-fork", hash_tree(t1), hash_tree(t2));
      };
      case (#labeled(l,t)) {
        h3("\13ic-hashtree-labeled", l, hash_tree(t));
      };
      case (#leaf(v)) {
        h2("\10ic-hashtree-leaf", v)
      };
      case (#pruned(h)) {
        h
      }
    }
  };

/*
The CBOR encoding of a HashTree, according to
https://sdk.dfinity.org/docs/interface-spec/index.html#certification-encoding
This data structure needs only very few features of CBOR, so instead of writing
a full-fledged CBOR encoding library, I just directly write out the bytes for the
few construct we need here.
*/

  func cbor_tree(tree : HashTree) : Blob {
    let buf = Buffer.Buffer<Nat8>(100);

    // CBOR self-describing tag
    buf.add(0xD9);
    buf.add(0xD9);
    buf.add(0xF7);

    func add_blob(b: Blob) {
      // Only works for blobs with less than 256 bytes
      buf.add(0x58);
      buf.add(Nat8.fromNat(b.size()));
      for (c in Blob.toArray(b).vals()) {
        buf.add(c);
      };
    };

    func go(t : HashTree) {
      switch (t) {
        case (#empty)        { buf.add(0x81); buf.add(0x00); };
        case (#fork(t1,t2))  { buf.add(0x83); buf.add(0x01); go(t1); go (t2); };
        case (#labeled(l,t)) { buf.add(0x83); buf.add(0x02); add_blob(l); go (t); };
        case (#leaf(v))      { buf.add(0x82); buf.add(0x03); add_blob(v); };
        case (#pruned(h))    { buf.add(0x82); buf.add(0x04); add_blob(h); }
      }
    };

    go(tree);

    return Blob.fromArray(buf.toArray());
  };
};
