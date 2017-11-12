xquery version "3.1";

module namespace app="http://dracor.org/ns/exist/templates";

import module namespace templates="http://exist-db.org/xquery/templates" ;
import module namespace config="http://dracor.org/ns/exist/config" at "config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : @param $node the HTML node with the attribute which triggered this call
 : @param $model a map containing arbitrary data - used to pass information between template calls
 :)
declare function app:stats($node as node(), $model as map(*)) {
  let $col := collection(concat($config:data-root, "/rus"))
  let $format := "#,###.##"
  let $num-docs := count($col/tei:TEI)
  let $num-persons := count($col//tei:listPerson/tei:person)
  let $num-male := count($col//tei:listPerson/tei:person[@sex="MALE"])
  let $num-female := count($col//tei:listPerson/tei:person[@sex="FEMALE"])
  let $num-text := count($col//tei:text)
  let $num-stage := count($col//tei:stage)
  let $num-sp := count($col//tei:sp)

  return
    <table class="table">
      <tr>
        <th>Number of plays</th>
        <td>{format-number($num-docs, $format)}</td>
      </tr>
      <tr>
        <th>Number of characters</th>
        <td>{format-number($num-persons, $format)}</td>
      </tr>
      <tr>
        <th>Male characters</th>
        <td>{format-number($num-male, $format)}</td>
      </tr>
      <tr>
        <th>Female characters</th>
        <td>{format-number($num-female, $format)}</td>
      </tr>
      <tr>
        <th>
          <code>text</code>
        </th>
        <td>
          {format-number($num-text, $format)}
        </td>
      </tr>
      <tr>
        <th>
          <code>stage</code> elements
        </th>
        <td>
          {format-number($num-stage, $format)}
        </td>
      </tr>
      <tr>
        <th><code>sp</code> elements</th>
        <td>
          {format-number($num-sp, $format)}
        </td>
      </tr>
    </table>
};
