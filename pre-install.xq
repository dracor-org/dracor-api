xquery version "1.0";

import module namespace xdb="http://exist-db.org/xquery/xmldb";
import module namespace config="http://dracor.org/ns/exist/v1/config"
  at "modules/config.xqm";

(: The following external variables are set by the repo:deploy function :)

(: file path pointing to the exist installation directory :)
declare variable $home external;
(: path to the directory containing the unpacked .xar package :)
declare variable $dir external;
(: the target collection into which the app is deployed :)
declare variable $target external;

declare function local:mkcol-recursive($collection, $components) {
    if (exists($components)) then
        let $newColl := concat($collection, "/", $components[1])
        return (
            xdb:create-collection($collection, $components[1]),
            local:mkcol-recursive($newColl, subsequence($components, 2))
        )
    else
        ()
};

(: Helper function to recursively create a collection hierarchy. :)
declare function local:mkcol($collection, $path) {
    local:mkcol-recursive($collection, tokenize($path, "/"))
};

(: store the collection configuration :)
local:mkcol("/db/system/config", $target),
xdb:store-files-from-pattern(
  concat("/db/system/config", $target), $dir, "collection.xconf"
),
xdb:create-collection("/", $config:data-root),
local:mkcol("/db/system/config", $config:data-root),
xdb:store-files-from-pattern(
  concat("/db/system/config", $config:data-root), $dir, "data.xconf"
),
xdb:create-collection("/", $config:rdf-root),
xdb:create-collection("/", $config:metrics-root),
xdb:create-collection("/", $config:sitelinks-root),
xdb:create-collection("/", $config:webhook-root)
