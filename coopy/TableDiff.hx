// -*- mode:java; tab-width:4; c-basic-offset:4; indent-tabs-mode:nil -*-

#if !TOPLEVEL
package coopy;
#end

/**
 *
 * Build a highlighter diff of two/three tables.
 *
 */
@:expose
class TableDiff {
    private var align : Alignment;
    private var flags : CompareFlags;
    private var builder : CellBuilder;

    /**
     *
     * Constructor.
     *
     * @param align a pre-computed alignment of the tables involved
     * @param flags options to control the appearance of the diff
     *
     */
    public function new(align: Alignment, flags: CompareFlags) {
        this.align = align;
        this.flags = flags;
        builder = null;
    }

    /**
     *
     * If you wish to customize how diff cells are generated,
     * call this prior to calling `hilite()`.
     *
     * @param builder hooks to generate custom cells
     *
     */
    public function setCellBuilder(builder: CellBuilder) {
        this.builder = builder;
    }

    private function getSeparator(t: Table,
                                 t2: Table, root: String) : String {
        var sep : String = root;
        var w : Int = t.width;
        var h : Int = t.height;
        var view : View = t.getCellView();
        for (y in 0...h) {
            for (x in 0...w) {
                var txt : String = view.toString(t.getCell(x,y));
                if (txt==null) continue;
                while (txt.indexOf(sep)>=0) {
                    sep = "-" + sep;
                }
            }
        }
        if (t2!=null) {
            w = t2.width;
            h = t2.height;
            for (y in 0...h) {
                for (x in 0...w) {
                    var txt : String = view.toString(t2.getCell(x,y));
                    if (txt==null) continue;
                    while (txt.indexOf(sep)>=0) {
                        sep = "-" + sep;
                    }
                }
            }
        }
        return sep;
    }

    private function quoteForDiff(v: View, d: Dynamic) : String {
        var nil : String = "NULL";
        if (v.equals(d,null)) {
            return nil;
        }
        var str : String = v.toString(d);
        var score : Int = 0;
        for (i in 0...str.length) {
            if (str.charCodeAt(score)!='_'.code) break;
            score++;
        }
        if (str.substr(score)==nil) {
            str = "_" + str;
        }
        return str;
    }

    private function isReordered(m: Map<Int,Unit>, ct: Int) : Bool {
        var reordered : Bool = false;
        var l : Int = -1;
        var r : Int = -1;
        for (i in 0...ct) {
            var unit : Unit = m.get(i);
            if (unit==null) continue;
            if (unit.l>=0) {
                if (unit.l<l) {
                    reordered = true;
                    break;
                }
                l = unit.l;
            }
            if (unit.r>=0) {
                if (unit.r<r) {
                    reordered = true;
                    break;
                }
                r = unit.r;
            }
        }
        return reordered;
    }


    private function spreadContext(units: Array<Unit>, 
                                   del: Int,
                                   active: Array<Int>) : Void {
        if (del>0 && active != null) {
            // forward
            var mark : Int = -del-1;
            var skips : Int = 0;
            for (i in 0...units.length) {
                if (active[i]==-3) {
                    // inserted/deleted row that is not to be shown, ignore
                    skips++;
                    continue;
                }
                if (active[i]==0||active[i]==3) {
                    if (i-mark<=del+skips) {
                        active[i] = 2;
                    } else if (i-mark==del+1+skips) {
                        active[i] = 3;
                    }
                } else if (active[i]==1) {
                    mark = i;
                    skips = 0;
                }
            }
            
            // reverse
            mark = units.length + del + 1;
            skips = 0;
            for (j in 0...units.length) {
                var i : Int = units.length-1-j;
                if (active[i]==-3) {
                    // inserted/deleted row that is not to be shown, ignore
                    skips++;
                    continue;
                }
                if (active[i]==0||active[i]==3) {
                    if (mark-i<=del+skips) {
                        active[i] = 2;
                    } else if (mark-i==del+1+skips) {
                        active[i] = 3;
                    }
                } else if (active[i]==1) {
                    mark = i;
                    skips = 0;
                }
            }
        }
    }

    private function setIgnore(ignore: Map<String,Bool>,
                               idx_ignore: Map<Int,Bool>,
                               tab: Table,
                               r_header: Int) : Void {
        var v = tab.getCellView();
        if (tab.height>=r_header) {
            for (i in 0...tab.width) {
                var name = v.toString(tab.getCell(i,r_header));
                if (!ignore.exists(name)) continue;
                idx_ignore.set(i,true);
            }
        }
    }

    private function countActive(active: Array<Int>) : Int {
        var ct = 0;
        var showed_dummy = false;
        for (i in 0...active.length) {
            var publish = active[i]>0;
            var dummy = active[i]==3;
            if (dummy&&showed_dummy) continue;
            if (!publish) continue;
            showed_dummy = dummy;
            ct++;
        }
        return ct;
    }

    /**
     *
     * Generate a highlighter diff.
     * @param output the table in which to place the diff - it can then
     * be converted to html using `DiffRender`
     * @return true on success
     *
     */
    public function hilite(output: Table) : Bool { 
        if (!output.isResizable()) return false;
        if (builder==null) {
            if (flags.allow_nested_cells) {
                builder = new NestedCellBuilder();
            } else {
                builder = new FlatCellBuilder(flags);
            }
        }
        output.resize(0,0);
        output.clear();

        var row_map : Map<Int,Unit> = new Map<Int,Unit>();
        var col_map : Map<Int,Unit> = new Map<Int,Unit>();

        var order : Ordering = align.toOrder();
        var units : Array<Unit> = order.getList();
        var has_parent : Bool = (align.reference != null);
        var a : Table;
        var b : Table;
        var p : Table;
        var rp_header : Int = 0;
        var ra_header : Int = 0;
        var rb_header : Int = 0;
        var is_index_p : Map<Int,Bool> = new Map<Int,Bool>();
        var is_index_a : Map<Int,Bool> = new Map<Int,Bool>();
        var is_index_b : Map<Int,Bool> = new Map<Int,Bool>();
        if (has_parent) {
            p = align.getSource();
            a = align.reference.getTarget();
            b = align.getTarget();
            rp_header = align.reference.meta.getSourceHeader();
            ra_header = align.reference.meta.getTargetHeader();
            rb_header = align.meta.getTargetHeader();
            if (align.getIndexColumns()!=null) {
                for (p2b in align.getIndexColumns()) {
                    if (p2b.l>=0) is_index_p.set(p2b.l,true);
                    if (p2b.r>=0) is_index_b.set(p2b.r,true);
                }
            }
            if (align.reference.getIndexColumns()!=null) {
                for (p2a in align.reference.getIndexColumns()) {
                    if (p2a.l>=0) is_index_p.set(p2a.l,true);
                    if (p2a.r>=0) is_index_a.set(p2a.r,true);
                }
            }
        } else {
            a = align.getSource();
            b = align.getTarget();
            p = a;
            ra_header = align.meta.getSourceHeader();
            rp_header = ra_header;
            rb_header = align.meta.getTargetHeader();
            if (align.getIndexColumns()!=null) {
                for (a2b in align.getIndexColumns()) {
                    if (a2b.l>=0) is_index_a.set(a2b.l,true);
                    if (a2b.r>=0) is_index_b.set(a2b.r,true);
                }
            }
        }

        var column_order : Ordering = align.meta.toOrder();
        var column_units : Array<Unit> = column_order.getList();

        var p_ignore = new Map<Int,Bool>();
        var a_ignore = new Map<Int,Bool>();
        var b_ignore = new Map<Int,Bool>();
        var ignore = flags.getIgnoredColumns();
        if (ignore!=null) {
            setIgnore(ignore,p_ignore,p,rp_header);
            setIgnore(ignore,a_ignore,a,ra_header);
            setIgnore(ignore,b_ignore,b,rb_header);

            var ncolumn_units = new Array<Unit>();
            for (j in 0...column_units.length) {
                var cunit : Unit = column_units[j];
                if (p_ignore.exists(cunit.p)||
                    a_ignore.exists(cunit.l)||
                    b_ignore.exists(cunit.r)) continue;
                ncolumn_units.push(cunit);
            }
            column_units = ncolumn_units;
        }

        var show_rc_numbers : Bool = false;
        var row_moves : Map<Int,Int> = null;
        var col_moves : Map<Int,Int> = null;
        if (flags.ordered) {
            row_moves = new Map<Int,Int>();
            var moves : Array<Int> = Mover.moveUnits(units);
            for (i in 0...moves.length) {
                row_moves[moves[i]] = i;
            }
            col_moves = new Map<Int,Int>();
            moves = Mover.moveUnits(column_units);
            for (i in 0...moves.length) {
                col_moves[moves[i]] = i;
            }
        }

        var active : Array<Int> = new Array<Int>();
        var active_column : Array<Int> = null;
        if (!flags.show_unchanged) {
            for (i in 0...units.length) {
                // flip assignment order for php efficiency :-)
                active[units.length-1-i] = 0;
            }
        }

        var allow_insert : Bool = flags.allowInsert();
        var allow_delete : Bool = flags.allowDelete();
        var allow_update : Bool = flags.allowUpdate();

        if (!flags.show_unchanged_columns) {
            active_column = new Array<Int>();
            for (i in 0...column_units.length) {
                var v : Int = 0;
                var unit : Unit = column_units[i];
                if (unit.l>=0 && is_index_a.get(unit.l)) v = 1;
                if (unit.r>=0 && is_index_b.get(unit.r)) v = 1;
                if (unit.p>=0 && is_index_p.get(unit.p)) v = 1;
                active_column[i] = v;
            }
        }

        var v : View = a.getCellView();
        builder.setView(v);

        var outer_reps_needed : Int = 
            (flags.show_unchanged&&flags.show_unchanged_columns) ? 1 : 2;

        var sep : String = "";
        var conflict_sep : String = "";

        var schema : Array<String> = new Array<String>();
        var have_schema : Bool = false;
        for (j in 0...column_units.length) {
            var cunit : Unit = column_units[j];
            var reordered : Bool = false;
            
            if (flags.ordered) {
                if (col_moves.exists(j)) {
                    reordered = true;
                }
                if (reordered) show_rc_numbers = true;
            }

            var act : String = "";
            if (cunit.r>=0 && cunit.lp()==-1) {
                have_schema = true;
                act = "+++";
                if (active_column!=null) {
                    if (allow_update) active_column[j] = 1;
                }
            }
            if (cunit.r<0 && cunit.lp()>=0) {
                have_schema = true;
                act = "---";
                if (active_column!=null) {
                    if (allow_update) active_column[j] = 1;
                }
            }
            if (cunit.r>=0 && cunit.lp()>=0) {
                if (p.height>=rp_header && b.height>=rb_header) {
                    var pp : Dynamic = p.getCell(cunit.lp(),rp_header);
                    var bb : Dynamic = b.getCell(cunit.r,rb_header);
                    if (!v.equals(pp,bb)) {
                        have_schema = true;
                        act = "(";
                        act += v.toString(pp);
                        act += ")";
                        if (active_column!=null) active_column[j] = 1;
                    }
                }
            }
            if (reordered) {
                act = ":" + act;
                have_schema = true;
                if (active_column!=null) active_column = null; // bail
            }

            schema.push(act);
        }
        if (have_schema) {
            var at : Int = output.height;
            output.resize(column_units.length+1,at+1);
            output.setCell(0,at,builder.marker("!"));
            for (j in 0...column_units.length) {
                output.setCell(j+1,at,v.toDatum(schema[j]));
            }
        }

        var top_line_done : Bool = false;
        if (flags.always_show_header) {
            var at : Int = output.height;
            output.resize(column_units.length+1,at+1);
            output.setCell(0,at,builder.marker("@@"));
            for (j in 0...column_units.length) {
                var cunit : Unit = column_units[j];
                if (cunit.r>=0) {
                    if (b.height!=0) {
                        output.setCell(j+1,at,
                                       b.getCell(cunit.r,rb_header));
                    }
                } else if (cunit.lp()>=0) {
                    if (p.height!=0) {
                        output.setCell(j+1,at,
                                       p.getCell(cunit.lp(),rp_header));
                    }
                }
                col_map.set(j+1,cunit);
            }
            top_line_done = true;
        }

#if php
        // Under PHP, it is going to be better to repeat the loop,
        // so we don't end up resizing our table bit by bit - this is 
        // super slow under PHP for large tables
        outer_reps_needed = 2;
#end

        var output_height : Int = output.height;
        var output_height_init : Int = output.height;
        // If we are dropping unchanged rows/cols, we repeat this loop twice.
        for (out in 0...outer_reps_needed) {
            if (out==1) {
                spreadContext(units,flags.unchanged_context,active);
                spreadContext(column_units,flags.unchanged_column_context,
                              active_column);
                if (active_column!=null) {
                    for (i in 0...column_units.length) {
                        if (active_column[i]==3) {
                            active_column[i] = 0;
                        }
                    }
                }
                var rows : Int = countActive(active)+output_height_init;
                if (top_line_done) rows--;
                output_height = output_height_init;
                if (rows>output.height) {
                    output.resize(column_units.length+1,rows);
                }
            }

            var showed_dummy : Bool = false;
            var l : Int = -1;
            var r : Int = -1;
            for (i in 0...units.length) {
                var unit : Unit = units[i];
                var reordered : Bool = false;

                if (flags.ordered) {
                    if (row_moves.exists(i)) {
                        reordered = true;
                    }
                    if (reordered) show_rc_numbers = true;
                }

                if (unit.r<0 && unit.l<0) continue;
                
                if (unit.r==0 && unit.lp()==0 && top_line_done) continue;

                var act : String = "";

                if (reordered) act = ":";

                var publish : Bool = flags.show_unchanged;
                var dummy : Bool = false;
                if (out==1) {
                    publish = active[i]>0;
                    dummy = active[i]==3;
                    if (dummy&&showed_dummy) continue;
                    if (!publish) continue;
                }

                if (!dummy) showed_dummy = false;

                var at : Int = output_height;
                if (publish) {
                    output_height++;
                    if (output.height<output_height) {
                        output.resize(column_units.length+1,output_height);
                    }
                }
                if (dummy) {
                    for (j in 0...(column_units.length+1)) {
                        output.setCell(j,at,v.toDatum("..."));
                    }
                    showed_dummy = true;
                    continue;
                }
                
                var have_addition : Bool = false;
                var skip : Bool = false;
                
                if (unit.p<0 && unit.l<0 && unit.r>=0) {
                    if (!allow_insert) skip = true;
                    act = "+++";
                }
                if ((unit.p>=0||!has_parent) && unit.l>=0 && unit.r<0) {
                    if (!allow_delete) skip = true;
                    act = "---";
                }

                if (skip) {
                    if (!publish) {
                        if (active!=null) {
                            active[i] = -3;
                        }
                    }
                    continue;
                }

                for (j in 0...column_units.length) {
                    var cunit : Unit = column_units[j];
                    var pp : Dynamic = null;
                    var ll : Dynamic = null;
                    var rr : Dynamic = null;
                    var dd : Dynamic = null;
                    var dd_to : Dynamic = null;
                    var have_dd_to : Bool = false;
                    var dd_to_alt : Dynamic = null;
                    var have_dd_to_alt : Bool = false;
                    var have_pp : Bool = false;
                    var have_ll : Bool = false;
                    var have_rr : Bool = false;
                    if (cunit.p>=0 && unit.p>=0) {
                        pp = p.getCell(cunit.p,unit.p);
                        have_pp = true;
                    }
                    if (cunit.l>=0 && unit.l>=0) {
                        ll = a.getCell(cunit.l,unit.l);
                        have_ll = true;
                    }
                    if (cunit.r>=0 && unit.r>=0) {
                        rr = b.getCell(cunit.r,unit.r);
                        have_rr = true;
                        if ((have_pp ? cunit.p : cunit.l)<0) {
                            if (rr != null) {
                                if (v.toString(rr) != "") {
                                    if (flags.allowUpdate()) {
                                        have_addition = true;
                                    }
                                }
                            }
                        }
                    }

                    // for now, just interested in p->r
                    if (have_pp) {
                        if (!have_rr) {
                            dd = pp;
                        } else {
                            // have_pp, have_rr
                            if (v.equals(pp,rr)) {
                                dd = pp;
                            } else {
                                // rr is different
                                dd = pp;
                                dd_to = rr;
                                have_dd_to = true;

                                if (!v.equals(pp,ll)) {
                                    if (!v.equals(pp,rr)) {
                                        dd_to_alt = ll;
                                        have_dd_to_alt = true;
                                    }
                                }
                            }
                        }
                    } else if (have_ll) {
                        if (!have_rr) {
                            dd = ll;
                        } else {
                            if (v.equals(ll,rr)) {
                                dd = ll;
                            } else {
                                // rr is different
                                dd = ll;
                                dd_to = rr;
                                have_dd_to = true;
                            }
                        }
                    } else {
                        dd = rr;
                    }

                    var cell : Dynamic = dd;
                    if (have_dd_to&&allow_update) {
                        if (active_column!=null) {
                            active_column[j] = 1;
                        }
                        // modification: x -> y
                        if (sep=="") {
                            if (builder.needSeparator()) {
                                // strictly speaking getSeparator(a,null,..)
                                // would be ok - but very confusing
                                sep = getSeparator(a,b,"->");
                                builder.setSeparator(sep);
                            } else {
                                sep = "->";
                            }
                        }
                        var is_conflict : Bool = false;
                        if (have_dd_to_alt) {
                            if (!v.equals(dd_to,dd_to_alt)) {
                                is_conflict = true;
                            }
                        }
                        if (!is_conflict) {
                            cell = builder.update(dd,dd_to);
                            if (sep.length>act.length) {
                                act = sep;
                            }
                        } else {
                            if (conflict_sep=="") {
                                if (builder.needSeparator()) {

                                    conflict_sep = getSeparator(p,a,"!") + sep;
                                    builder.setConflictSeparator(conflict_sep);
                                } else {
                                    conflict_sep = "!->";
                                }
                            }
                            cell = builder.conflict(dd,dd_to_alt,dd_to);
                            act = conflict_sep;
                        }
                    }
                    if (act == "" && have_addition) {
                        act = "+";
                    }
                    if (act == "+++") {
                        if (have_rr) {
                            if (active_column!=null) {
                                active_column[j] = 1;
                            }
                        }
                    }
                    if (publish) {
                        if (active_column==null || active_column[j]>0) {
                            output.setCell(j+1,at,cell);
                        }
                    }
                }

                if (publish) {
                    output.setCell(0,at,builder.marker(act));
                    row_map.set(at,unit);
                }
                if (act!="") {
                    if (!publish) {
                        if (active!=null) {
                            active[i] = 1;
                        }
                    }
                }
            }
        }

        // add row/col numbers?
        if (!show_rc_numbers) {
            if (flags.always_show_order) {
                show_rc_numbers = true;
            } else if (flags.ordered) {
                show_rc_numbers = isReordered(row_map,output.height);
                if (!show_rc_numbers) {
                    show_rc_numbers = isReordered(col_map,output.width);
                }
            }
        }

        var admin_w : Int = 1;
        if (show_rc_numbers&&!flags.never_show_order) {
            admin_w++;
            var target : Array<Int> = new Array<Int>();
            for (i in 0...output.width) {
                target.push(i+1);
            }
            output.insertOrDeleteColumns(target,output.width+1);

            for (i in 0...output.height) {
                var unit : Unit = row_map.get(i);
                if (unit==null) {
                    output.setCell(0,i,"");
                    continue;
                }
                output.setCell(0,i,builder.links(unit,true));
            }
            target = new Array<Int>();
            for (i in 0...output.height) {
                target.push(i+1);
            }
            output.insertOrDeleteRows(target,output.height+1);
            for (i in 1...output.width) {
                var unit : Unit = col_map.get(i-1);
                if (unit==null) {
                    output.setCell(i,0,"");
                    continue;
                }
                output.setCell(i,0,builder.links(unit,false));
            }
            output.setCell(0,0,builder.marker("@:@"));
        }

        if (active_column!=null) {
            var all_active : Bool = true;
            for (i in 0...active_column.length) {
                if (active_column[i]==0) {
                    all_active = false;
                    break;
                }
            }
            if (!all_active) {
                var fate : Array<Int> = new Array<Int>();
                for (i in 0...admin_w) {
                    fate.push(i);
                }
                var at : Int = admin_w;
                var ct : Int = 0;
                var dots : Array<Int> = new Array<Int>();
                for (i in 0...active_column.length) {
                    var off : Bool = (active_column[i]==0);
                    ct = off ? (ct+1) : 0;
                    if (off && ct>1) {
                        fate.push(-1);
                    } else {
                        if (off) dots.push(at);
                        fate.push(at);
                        at++;
                    }
                }
                output.insertOrDeleteColumns(fate,at);
                for (d in dots) {
                    for (j in 0...output.height) {
                        output.setCell(d,j,builder.marker("..."));
                    }
                }
            }
        }
        return true;
    }
}

