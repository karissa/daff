// -*- mode:java; tab-width:4; c-basic-offset:4; indent-tabs-mode:nil -*-

#if !TOPLEVEL
package coopy;
#end

@:noDoc
class Index {
    public var items : Map<String,IndexItem>;
    public var keys : Array<String>;
    public var top_freq : Int;
    public var height : Int;

    private var cols : Array<Int>;
    private var v : View;
    private var indexed_table : Table;
    private var hdr : Int;

    public function new() : Void {
        items = new Map<String,IndexItem>();
        cols = new Array<Int>();
        keys = new Array<String>();
        top_freq = 0;
        height = 0;
        hdr = 0;
    }
 
    public function addColumn(i: Int) : Void {
        cols.push(i);
    }

    public function indexTable(t: Table, hdr: Int) : Void {
        indexed_table = t;
        this.hdr = hdr;
        if (keys.length!=t.height && t.height>0) {
            // preallocate array, helpful for php
            keys[t.height-1] = null;
        }
        for (i in 0...t.height) {
            var key : String = keys[i];
            if (key==null) {
                key = toKey(t,i);
                keys[i] = key;
            }
            var item : IndexItem = items.get(key);
            if (item==null) {
                item = new IndexItem();
                items.set(key,item);
            }
            var ct : Int = item.add(i);
            if (ct>top_freq) top_freq = ct;
        }
        height = t.height;
    }

    public function toKey(t: Table, 
                          i: Int) : String {
        var wide : String = (i<hdr)?"_":"";
        if (v==null) v = t.getCellView();
        for (k in 0...cols.length) {
            var d : Dynamic = t.getCell(cols[k],i);
            var txt : String = v.toString(d);
            if (k>0) wide += " // ";
            if (txt==null || txt=="" || txt=="null" || txt=="undefined") continue;
            wide += txt;
        }
        return wide;
    }

    public function toKeyByContent(row: Row) : String {
        var wide : String = row.isPreamble()?"_":"";
        for (k in 0...cols.length) {
            var txt : String = row.getRowString(cols[k]);
            if (k>0) wide += " // ";
            if (txt==null || txt=="" || txt=="null" || txt=="undefined") continue;
            wide += txt;
        }
        return wide;
    }

    public function getTable() : Table {
        return indexed_table;
    }
}
