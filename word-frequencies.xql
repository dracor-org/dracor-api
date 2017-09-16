xquery version "3.1";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare option exist:serialize "method=text media-type=text/plain ident=no";

let $col := collection("/db/data/dracor")
let $name := request:get-parameter("elem", "stage")
let $terms :=
  <terms>
    {
      util:index-keys(
        collection("/db/data/dracor")//tei:*[name() eq $name], "",
        function($key, $count) {
          <term name="{$key}" count="{$count[1]}"docs="{$count[2]}" pos="{$count[3]}"/>
        },
        -1,
        "lucene-index"
      )
    }
  </terms>

for $t in $terms/term
order by number($t/@count) descending
return concat($t/@name, ", ", $t/@count, ", ", $t/@docs, "
")
