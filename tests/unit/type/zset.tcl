start_server {tags {"zset"}} {
    proc create_zset {key items} {
        r del $key
        foreach {score entry} $items {
            r zadd $key $score $entry
        }
    }

    proc basics {encoding} {
        if {$encoding == "ziplist"} {
            r config set zset-max-ziplist-entries 128
            r config set zset-max-ziplist-value 64
        } elseif {$encoding == "skiplist"} {
            r config set zset-max-ziplist-entries 0
            r config set zset-max-ziplist-value 0
        } else {
            puts "Unknown sorted set encoding"
            exit
        }

        test "Check encoding - $encoding" {
            r del ztmp
            r zadd ztmp 10 x
            assert_encoding $encoding ztmp
        }

        test "ZSET basic ZADD and score update - $encoding" {
            r del ztmp
            r zadd ztmp 10 x
            r zadd ztmp 20 y
            r zadd ztmp 30 z
            assert_equal {x y z} [r zrange ztmp 0 -1]

            r zadd ztmp 1 y
            assert_equal {y x z} [r zrange ztmp 0 -1]
        }

        test "ZSET element can't be set to NaN with ZADD - $encoding" {
            assert_error "*not a double*" {r zadd myzset nan abc}
        }

        test "ZSET element can't be set to NaN with ZINCRBY" {
            assert_error "*not a double*" {r zadd myzset nan abc}
        }

        test "ZINCRBY calls leading to NaN result in error" {
            r zincrby myzset +inf abc
            assert_error "*NaN*" {r zincrby myzset -inf abc}
        }

        test "ZADDNX basics - $encoding" {
            r del znx
            r zadd znx 1 a
            set a1 [r zaddnx znx 2 b]
            set a2 [r zaddnx znx 3 a]
            set a3 [r zrange znx 0 -1]
            list $a1 $a2 $a3
        } {1 0 {a b}}

        test "ZADDCMP basics - $encoding" {
            r del zcmp
            r zadd zcmp 1 a
            set a1 [r zaddcmp zcmp 2 b]
            set a2 [r zaddcmp zcmp 3 a]
            set a3 [r zaddcmp zcmp 1 a]
            set a4 [r zrange zcmp 0 -1]
            set a5 [r zaddcmp zcmp 2 a min]
            set a6 [r zaddcmp zcmp 4 b max]
            set a7 [r zaddcmp zcmp 5 c min]
            set a8 [r zaddcmp zcmp 6 d max]
            set a9 [r zaddcmp zcmp 7 a min]
            set a10 [r zrange zcmp 0 -1]
            list $a1 $a2 $a3 $a4 $a5 $a6 $a7 $a8 $a9 $a10
        } {1 1 0 {b a} 1 1 1 1 0 {a b c d}}

        test {ZADD - Variadic version base case} {
            r del myzset
            list [r zadd myzset 10 a 20 b 30 c] [r zrange myzset 0 -1 withscores]
        } {3 {a 10 b 20 c 30}}

        test {ZADD - Return value is the number of actually added items} {
            list [r zadd myzset 5 x 20 b 30 c] [r zrange myzset 0 -1 withscores]
        } {1 {x 5 a 10 b 20 c 30}}

        test {ZADD - Variadic version does not add nothing on single parsing err} {
            r del myzset
            catch {r zadd myzset 10 a 20 b 30.badscore c} e
            assert_match {*ERR*not*double*} $e
            r exists myzset
        } {0}

        test {ZADD - Variadic version will raise error on missing arg} {
            r del myzset
            catch {r zadd myzset 10 a 20 b 30 c 40} e
            assert_match {*ERR*syntax*} $e
        }

        test {ZINCRBY does not work variadic even if shares ZADD implementation} {
            r del myzset
            catch {r zincrby myzset 10 a 20 b 30 c} e
            assert_match {*ERR*wrong*number*arg*} $e
        }

        test "ZCARD basics - $encoding" {
            assert_equal 3 [r zcard ztmp]
            assert_equal 0 [r zcard zdoesntexist]
        }

        test "ZREM removes key after last element is removed" {
            r del ztmp
            r zadd ztmp 10 x
            r zadd ztmp 20 y

            assert_equal 1 [r exists ztmp]
            assert_equal 0 [r zrem ztmp z]
            assert_equal 1 [r zrem ztmp y]
            assert_equal 1 [r zrem ztmp x]
            assert_equal 0 [r exists ztmp]
        }

        test "ZREM variadic version" {
            r del ztmp
            r zadd ztmp 10 a 20 b 30 c
            assert_equal 2 [r zrem ztmp x y a b k]
            assert_equal 0 [r zrem ztmp foo bar]
            assert_equal 1 [r zrem ztmp c]
            r exists ztmp
        } {0}

        test "ZREM variadic version -- remove elements after key deletion" {
            r del ztmp
            r zadd ztmp 10 a 20 b 30 c
            r zrem ztmp a b c d e f g
        } {3}

        test "ZRANGE basics - $encoding" {
            r del ztmp
            r zadd ztmp 1 a
            r zadd ztmp 2 b
            r zadd ztmp 3 c
            r zadd ztmp 4 d

            assert_equal {a b c d} [r zrange ztmp 0 -1]
            assert_equal {a b c} [r zrange ztmp 0 -2]
            assert_equal {b c d} [r zrange ztmp 1 -1]
            assert_equal {b c} [r zrange ztmp 1 -2]
            assert_equal {c d} [r zrange ztmp -2 -1]
            assert_equal {c} [r zrange ztmp -2 -2]

            # out of range start index
            assert_equal {a b c} [r zrange ztmp -5 2]
            assert_equal {a b} [r zrange ztmp -5 1]
            assert_equal {} [r zrange ztmp 5 -1]
            assert_equal {} [r zrange ztmp 5 -2]

            # out of range end index
            assert_equal {a b c d} [r zrange ztmp 0 5]
            assert_equal {b c d} [r zrange ztmp 1 5]
            assert_equal {} [r zrange ztmp 0 -5]
            assert_equal {} [r zrange ztmp 1 -5]

            # withscores
            assert_equal {a 1 b 2 c 3 d 4} [r zrange ztmp 0 -1 withscores]
        }

        test "ZREVRANGE basics - $encoding" {
            r del ztmp
            r zadd ztmp 1 a
            r zadd ztmp 2 b
            r zadd ztmp 3 c
            r zadd ztmp 4 d

            assert_equal {d c b a} [r zrevrange ztmp 0 -1]
            assert_equal {d c b} [r zrevrange ztmp 0 -2]
            assert_equal {c b a} [r zrevrange ztmp 1 -1]
            assert_equal {c b} [r zrevrange ztmp 1 -2]
            assert_equal {b a} [r zrevrange ztmp -2 -1]
            assert_equal {b} [r zrevrange ztmp -2 -2]

            # out of range start index
            assert_equal {d c b} [r zrevrange ztmp -5 2]
            assert_equal {d c} [r zrevrange ztmp -5 1]
            assert_equal {} [r zrevrange ztmp 5 -1]
            assert_equal {} [r zrevrange ztmp 5 -2]

            # out of range end index
            assert_equal {d c b a} [r zrevrange ztmp 0 5]
            assert_equal {c b a} [r zrevrange ztmp 1 5]
            assert_equal {} [r zrevrange ztmp 0 -5]
            assert_equal {} [r zrevrange ztmp 1 -5]

            # withscores
            assert_equal {d 4 c 3 b 2 a 1} [r zrevrange ztmp 0 -1 withscores]
        }

        test "ZRANK/ZREVRANK basics - $encoding" {
            r del zranktmp
            r zadd zranktmp 10 x
            r zadd zranktmp 20 y
            r zadd zranktmp 30 z
            assert_equal 0 [r zrank zranktmp x]
            assert_equal 1 [r zrank zranktmp y]
            assert_equal 2 [r zrank zranktmp z]
            assert_equal "" [r zrank zranktmp foo]
            assert_equal 2 [r zrevrank zranktmp x]
            assert_equal 1 [r zrevrank zranktmp y]
            assert_equal 0 [r zrevrank zranktmp z]
            assert_equal "" [r zrevrank zranktmp foo]
        }

        test "ZRANK - after deletion - $encoding" {
            r zrem zranktmp y
            assert_equal 0 [r zrank zranktmp x]
            assert_equal 1 [r zrank zranktmp z]
        }

        test "ZINCRBY - can create a new sorted set - $encoding" {
            r del zset
            r zincrby zset 1 foo
            assert_equal {foo} [r zrange zset 0 -1]
            assert_equal 1 [r zscore zset foo]
        }

        test "ZINCRBY - increment and decrement - $encoding" {
            r zincrby zset 2 foo
            r zincrby zset 1 bar
            assert_equal {bar foo} [r zrange zset 0 -1]

            r zincrby zset 10 bar
            r zincrby zset -5 foo
            r zincrby zset -5 bar
            assert_equal {foo bar} [r zrange zset 0 -1]

            assert_equal -2 [r zscore zset foo]
            assert_equal  6 [r zscore zset bar]
        }

        proc create_default_zset {} {
            create_zset zset {-inf a 1 b 2 c 3 d 4 e 5 f +inf g}
        }

        test "ZRANGEBYSCORE/ZREVRANGEBYSCORE/ZCOUNT basics" {
            create_default_zset

            # inclusive range
            assert_equal {a b c} [r zrangebyscore zset -inf 2]
            assert_equal {b c d} [r zrangebyscore zset 0 3]
            assert_equal {d e f} [r zrangebyscore zset 3 6]
            assert_equal {e f g} [r zrangebyscore zset 4 +inf]
            assert_equal {c b a} [r zrevrangebyscore zset 2 -inf]
            assert_equal {d c b} [r zrevrangebyscore zset 3 0]
            assert_equal {f e d} [r zrevrangebyscore zset 6 3]
            assert_equal {g f e} [r zrevrangebyscore zset +inf 4]
            assert_equal 3 [r zcount zset 0 3]

            # exclusive range
            assert_equal {b}   [r zrangebyscore zset (-inf (2]
            assert_equal {b c} [r zrangebyscore zset (0 (3]
            assert_equal {e f} [r zrangebyscore zset (3 (6]
            assert_equal {f}   [r zrangebyscore zset (4 (+inf]
            assert_equal {b}   [r zrevrangebyscore zset (2 (-inf]
            assert_equal {c b} [r zrevrangebyscore zset (3 (0]
            assert_equal {f e} [r zrevrangebyscore zset (6 (3]
            assert_equal {f}   [r zrevrangebyscore zset (+inf (4]
            assert_equal 2 [r zcount zset (0 (3]

            # test empty ranges
            r zrem zset a
            r zrem zset g

            # inclusive
            assert_equal {} [r zrangebyscore zset 4 2]
            assert_equal {} [r zrangebyscore zset 6 +inf]
            assert_equal {} [r zrangebyscore zset -inf -6]
            assert_equal {} [r zrevrangebyscore zset +inf 6]
            assert_equal {} [r zrevrangebyscore zset -6 -inf]

            # exclusive
            assert_equal {} [r zrangebyscore zset (4 (2]
            assert_equal {} [r zrangebyscore zset 2 (2]
            assert_equal {} [r zrangebyscore zset (2 2]
            assert_equal {} [r zrangebyscore zset (6 (+inf]
            assert_equal {} [r zrangebyscore zset (-inf (-6]
            assert_equal {} [r zrevrangebyscore zset (+inf (6]
            assert_equal {} [r zrevrangebyscore zset (-6 (-inf]

            # empty inner range
            assert_equal {} [r zrangebyscore zset 2.4 2.6]
            assert_equal {} [r zrangebyscore zset (2.4 2.6]
            assert_equal {} [r zrangebyscore zset 2.4 (2.6]
            assert_equal {} [r zrangebyscore zset (2.4 (2.6]
        }

        test "ZRANGEBYSCORE with WITHSCORES" {
            create_default_zset
            assert_equal {b 1 c 2 d 3} [r zrangebyscore zset 0 3 withscores]
            assert_equal {d 3 c 2 b 1} [r zrevrangebyscore zset 3 0 withscores]
        }

        test "ZRANGEBYSCORE with LIMIT" {
            create_default_zset
            assert_equal {b c}   [r zrangebyscore zset 0 10 LIMIT 0 2]
            assert_equal {d e f} [r zrangebyscore zset 0 10 LIMIT 2 3]
            assert_equal {d e f} [r zrangebyscore zset 0 10 LIMIT 2 10]
            assert_equal {}      [r zrangebyscore zset 0 10 LIMIT 20 10]
            assert_equal {f e}   [r zrevrangebyscore zset 10 0 LIMIT 0 2]
            assert_equal {d c b} [r zrevrangebyscore zset 10 0 LIMIT 2 3]
            assert_equal {d c b} [r zrevrangebyscore zset 10 0 LIMIT 2 10]
            assert_equal {}      [r zrevrangebyscore zset 10 0 LIMIT 20 10]
        }

        test "ZRANGEBYSCORE with LIMIT and WITHSCORES" {
            create_default_zset
            assert_equal {e 4 f 5} [r zrangebyscore zset 2 5 LIMIT 2 3 WITHSCORES]
            assert_equal {d 3 c 2} [r zrevrangebyscore zset 5 2 LIMIT 2 3 WITHSCORES]
        }

        test "ZRANGEBYSCORE with non-value min or max" {
            assert_error "*not a double*" {r zrangebyscore fooz str 1}
            assert_error "*not a double*" {r zrangebyscore fooz 1 str}
            assert_error "*not a double*" {r zrangebyscore fooz 1 NaN}
        }

        test "ZREMRANGEBYSCORE basics" {
            proc remrangebyscore {min max} {
                create_zset zset {1 a 2 b 3 c 4 d 5 e}
                assert_equal 1 [r exists zset]
                r zremrangebyscore zset $min $max
            }

            # inner range
            assert_equal 3 [remrangebyscore 2 4]
            assert_equal {a e} [r zrange zset 0 -1]

            # start underflow
            assert_equal 1 [remrangebyscore -10 1]
            assert_equal {b c d e} [r zrange zset 0 -1]

            # end overflow
            assert_equal 1 [remrangebyscore 5 10]
            assert_equal {a b c d} [r zrange zset 0 -1]

            # switch min and max
            assert_equal 0 [remrangebyscore 4 2]
            assert_equal {a b c d e} [r zrange zset 0 -1]

            # -inf to mid
            assert_equal 3 [remrangebyscore -inf 3]
            assert_equal {d e} [r zrange zset 0 -1]

            # mid to +inf
            assert_equal 3 [remrangebyscore 3 +inf]
            assert_equal {a b} [r zrange zset 0 -1]

            # -inf to +inf
            assert_equal 5 [remrangebyscore -inf +inf]
            assert_equal {} [r zrange zset 0 -1]

            # exclusive min
            assert_equal 4 [remrangebyscore (1 5]
            assert_equal {a} [r zrange zset 0 -1]
            assert_equal 3 [remrangebyscore (2 5]
            assert_equal {a b} [r zrange zset 0 -1]

            # exclusive max
            assert_equal 4 [remrangebyscore 1 (5]
            assert_equal {e} [r zrange zset 0 -1]
            assert_equal 3 [remrangebyscore 1 (4]
            assert_equal {d e} [r zrange zset 0 -1]

            # exclusive min and max
            assert_equal 3 [remrangebyscore (1 (5]
            assert_equal {a e} [r zrange zset 0 -1]

            # destroy when empty
            assert_equal 5 [remrangebyscore 1 5]
            assert_equal 0 [r exists zset]
        }

        test "ZREMRANGEBYSCORE with non-value min or max" {
            assert_error "*not a double*" {r zremrangebyscore fooz str 1}
            assert_error "*not a double*" {r zremrangebyscore fooz 1 str}
            assert_error "*not a double*" {r zremrangebyscore fooz 1 NaN}
        }

        test "ZREMRANGEBYRANK basics" {
            proc remrangebyrank {min max} {
                create_zset zset {1 a 2 b 3 c 4 d 5 e}
                assert_equal 1 [r exists zset]
                r zremrangebyrank zset $min $max
            }

            # inner range
            assert_equal 3 [remrangebyrank 1 3]
            assert_equal {a e} [r zrange zset 0 -1]

            # start underflow
            assert_equal 1 [remrangebyrank -10 0]
            assert_equal {b c d e} [r zrange zset 0 -1]

            # start overflow
            assert_equal 0 [remrangebyrank 10 -1]
            assert_equal {a b c d e} [r zrange zset 0 -1]

            # end underflow
            assert_equal 0 [remrangebyrank 0 -10]
            assert_equal {a b c d e} [r zrange zset 0 -1]

            # end overflow
            assert_equal 5 [remrangebyrank 0 10]
            assert_equal {} [r zrange zset 0 -1]

            # destroy when empty
            assert_equal 5 [remrangebyrank 0 4]
            assert_equal 0 [r exists zset]
        }

        test "ZUNIONSTORE against non-existing key doesn't set destination - $encoding" {
            r del zseta
            assert_equal 0 [r zunionstore dst_key 1 zseta]
            assert_equal 0 [r exists dst_key]
        }

        test "ZUNIONSTORE with empty set - $encoding" {
            r del zseta zsetb
            r zadd zseta 1 a
            r zadd zseta 2 b
            r zunionstore zsetc 2 zseta zsetb
            r zrange zsetc 0 -1 withscores
        } {a 1 b 2}

        test "ZUNIONSTORE basics - $encoding" {
            r del zseta zsetb zsetc
            r zadd zseta 1 a
            r zadd zseta 2 b
            r zadd zseta 3 c
            r zadd zsetb 1 b
            r zadd zsetb 2 c
            r zadd zsetb 3 d

            assert_equal 4 [r zunionstore zsetc 2 zseta zsetb]
            assert_equal {a 1 b 3 d 3 c 5} [r zrange zsetc 0 -1 withscores]
        }

        test "ZUNIONSTORE with weights - $encoding" {
            assert_equal 4 [r zunionstore zsetc 2 zseta zsetb weights 2 3]
            assert_equal {a 2 b 7 d 9 c 12} [r zrange zsetc 0 -1 withscores]
        }

        test "ZUNIONSTORE with a regular set and weights - $encoding" {
            r del seta
            r sadd seta a
            r sadd seta b
            r sadd seta c

            assert_equal 4 [r zunionstore zsetc 2 seta zsetb weights 2 3]
            assert_equal {a 2 b 5 c 8 d 9} [r zrange zsetc 0 -1 withscores]
        }

        test "ZUNIONSTORE with AGGREGATE MIN - $encoding" {
            assert_equal 4 [r zunionstore zsetc 2 zseta zsetb aggregate min]
            assert_equal {a 1 b 1 c 2 d 3} [r zrange zsetc 0 -1 withscores]
        }

        test "ZUNIONSTORE with AGGREGATE MAX - $encoding" {
            assert_equal 4 [r zunionstore zsetc 2 zseta zsetb aggregate max]
            assert_equal {a 1 b 2 c 3 d 3} [r zrange zsetc 0 -1 withscores]
        }

        test "ZINTERSTORE basics - $encoding" {
            assert_equal 2 [r zinterstore zsetc 2 zseta zsetb]
            assert_equal {b 3 c 5} [r zrange zsetc 0 -1 withscores]
        }

        test "ZINTERSTORE with weights - $encoding" {
            assert_equal 2 [r zinterstore zsetc 2 zseta zsetb weights 2 3]
            assert_equal {b 7 c 12} [r zrange zsetc 0 -1 withscores]
        }

        test "ZINTERSTORE with a regular set and weights - $encoding" {
            r del seta
            r sadd seta a
            r sadd seta b
            r sadd seta c
            assert_equal 2 [r zinterstore zsetc 2 seta zsetb weights 2 3]
            assert_equal {b 5 c 8} [r zrange zsetc 0 -1 withscores]
        }

        test "ZINTERSTORE with AGGREGATE MIN - $encoding" {
            assert_equal 2 [r zinterstore zsetc 2 zseta zsetb aggregate min]
            assert_equal {b 1 c 2} [r zrange zsetc 0 -1 withscores]
        }

        test "ZINTERSTORE with AGGREGATE MAX - $encoding" {
            assert_equal 2 [r zinterstore zsetc 2 zseta zsetb aggregate max]
            assert_equal {b 2 c 3} [r zrange zsetc 0 -1 withscores]
        }

        foreach cmd {ZUNIONSTORE ZINTERSTORE} {
            test "$cmd with +inf/-inf scores - $encoding" {
                r del zsetinf1 zsetinf2

                r zadd zsetinf1 +inf key
                r zadd zsetinf2 +inf key
                r $cmd zsetinf3 2 zsetinf1 zsetinf2
                assert_equal inf [r zscore zsetinf3 key]

                r zadd zsetinf1 -inf key
                r zadd zsetinf2 +inf key
                r $cmd zsetinf3 2 zsetinf1 zsetinf2
                assert_equal 0 [r zscore zsetinf3 key]

                r zadd zsetinf1 +inf key
                r zadd zsetinf2 -inf key
                r $cmd zsetinf3 2 zsetinf1 zsetinf2
                assert_equal 0 [r zscore zsetinf3 key]

                r zadd zsetinf1 -inf key
                r zadd zsetinf2 -inf key
                r $cmd zsetinf3 2 zsetinf1 zsetinf2
                assert_equal -inf [r zscore zsetinf3 key]
            }

            test "$cmd with NaN weights $encoding" {
                r del zsetinf1 zsetinf2

                r zadd zsetinf1 1.0 key
                r zadd zsetinf2 1.0 key
                assert_error "*weight value is not a double*" {
                    r $cmd zsetinf3 2 zsetinf1 zsetinf2 weights nan nan
                }
            }
        }
    }

    basics ziplist
    basics skiplist

    test {ZINTERSTORE regression with two sets, intset+hashtable} {
        r del seta setb setc
        r sadd set1 a
        r sadd set2 10
        r zinterstore set3 2 set1 set2
    } {0}

    test {ZUNIONSTORE regression, should not create NaN in scores} {
        r zadd z -inf neginf
        r zunionstore out 1 z weights 0
        r zrange out 0 -1 withscores
    } {neginf 0}

    proc stressers {encoding} {
        if {$encoding == "ziplist"} {
            # Little extra to allow proper fuzzing in the sorting stresser
            r config set zset-max-ziplist-entries 256
            r config set zset-max-ziplist-value 64
            set elements 128
        } elseif {$encoding == "skiplist"} {
            r config set zset-max-ziplist-entries 0
            r config set zset-max-ziplist-value 0
            if {$::accurate} {set elements 1000} else {set elements 100}
        } else {
            puts "Unknown sorted set encoding"
            exit
        }

        test "ZSCORE - $encoding" {
            r del zscoretest
            set aux {}
            for {set i 0} {$i < $elements} {incr i} {
                set score [expr rand()]
                lappend aux $score
                r zadd zscoretest $score $i
            }

            assert_encoding $encoding zscoretest
            for {set i 0} {$i < $elements} {incr i} {
                assert_equal [lindex $aux $i] [r zscore zscoretest $i]
            }
        }

        test "ZSCORE after a DEBUG RELOAD - $encoding" {
            r del zscoretest
            set aux {}
            for {set i 0} {$i < $elements} {incr i} {
                set score [expr rand()]
                lappend aux $score
                r zadd zscoretest $score $i
            }

            r debug reload
            assert_encoding $encoding zscoretest
            for {set i 0} {$i < $elements} {incr i} {
                assert_equal [lindex $aux $i] [r zscore zscoretest $i]
            }
        }

        test "ZSUBSET basics - $encoding" {
            r del ztmp
            r zadd ztmp 10 x
            r zadd ztmp 20 y
            r zadd ztmp 30 a
            r zadd ztmp 40 b
            r zadd ztmp 50 c
            r zadd ztmp -10 w

            assert_equal {x} [r zsubset ztmp 1 x]
            assert_equal {y} [r zsubset ztmp 1 y]
            assert_equal {} [r zsubset ztmp 1 z]
            assert_equal {x y} [r zsubset ztmp 3 x y z]
            assert_equal {x y} [r zsubset ztmp 3 z x y]
            assert_equal {y x} [r zsubset ztmp 3 y z x]
            assert_equal {y x} [r zsubset ztmp 3 z y x]
            assert_equal {x} [r zsubset ztmp 3 q x t]
            assert_equal {y} [r zsubset ztmp 3 y q t]
            assert_equal {} [r zsubset ztmp 3 z q t]
            assert_equal {q x t} [r zsubset ztmp 3 q x t defaultscore 0]
            assert_equal {y q t} [r zsubset ztmp 3 y q t defaultscore 0]
            assert_equal {z q t} [r zsubset ztmp 3 z q t defaultscore 0]
        }

        test "ZSUBSET with WITHSCORES - $encoding" {
            assert_equal {x 10} [r zsubset ztmp 1 x withscores]
            assert_equal {y 20} [r zsubset ztmp 1 y withscores]
            assert_equal {} [r zsubset ztmp 1 z withscores]
            assert_equal {x 10 y 20} [r zsubset ztmp 3 x y z withscores]
            assert_equal {x 10 y 20} [r zsubset ztmp 3 z x y withscores]
            assert_equal {y 20 x 10} [r zsubset ztmp 3 y z x withscores]
            assert_equal {y 20 x 10} [r zsubset ztmp 3 z y x withscores]
            assert_equal {x 10} [r zsubset ztmp 3 q x t withscores]
            assert_equal {y 20} [r zsubset ztmp 3 y q t withscores]
            assert_equal {} [r zsubset ztmp 3 z q t withscores]
            assert_equal {q 0 x 10 t 0} [r zsubset ztmp 3 q x t withscores defaultscore 0]
            assert_equal {y 20 q 2 t 2} [r zsubset ztmp 3 y q t withscores defaultscore 2]
            assert_equal {z 4 q 4 t 4} [r zsubset ztmp 3 z q t withscores defaultscore 4]
        }

        test "ZSUBSET with MIN/MAX - $encoding" {
            assert_equal {a c} [r zsubset ztmp 4 a c z x min 20]
            assert_equal {a x} [r zsubset ztmp 4 a c z x max 40]
            assert_equal {} [r zsubset ztmp 4 a c z x min 100]
            assert_equal {} [r zsubset ztmp 4 a c z x max -20]
            assert_equal {a c} [r zsubset ztmp 4 a c z x min 20 defaultscore 0]
            assert_equal {a z x} [r zsubset ztmp 4 a c z x max 40 defaultscore 0]
            assert_equal {} [r zsubset ztmp 4 a c z x min 100 defaultscore 0]
            assert_equal {} [r zsubset ztmp 4 a c z x max -20 defaultscore 0]
        }

        test "ZSUBSET with LIMIT - $encoding" {
            assert_equal {x} [r zsubset ztmp 1 x limit 0 1]
            assert_equal {y} [r zsubset ztmp 1 y limit 0 1]
            assert_equal {x y} [r zsubset ztmp 2 x y limit 0 2]
            assert_equal {x} [r zsubset ztmp 2 x z limit 0 2]
            assert_equal {x} [r zsubset ztmp 3 x y z limit 0 1]
            assert_equal {x} [r zsubset ztmp 3 y z x limit 1 1]
            assert_equal {x y} [r zsubset ztmp 3 x y z limit 0 2]
            assert_equal {} [r zsubset ztmp 3 z y x limit 2 5]
            assert_equal {x z} [r zsubset ztmp 2 x z limit 0 2 defaultscore 0]
            assert_equal {x} [r zsubset ztmp 3 x y z limit 0 1 defaultscore 0]
            assert_equal {z} [r zsubset ztmp 3 y z x limit 1 1 defaultscore 0]
            assert_equal {} [r zsubset ztmp 3 z y x limit 3 5 defaultscore 0]
            assert_equal {x z} [r zsubset ztmp 3 x z y limit 0 2 defaultscore 0]
            assert_equal {x y} [r zsubset ztmp 4 a b x y limit 2 5 max 40]
            assert_equal {x y} [r zsubset ztmp 4 a b x y limit 0 3 max 20]
        }

        test "ZSUBSET with SORT - $encoding" {
            assert_equal {x a c} [r zsubset ztmp 4 a c z x sort]
            assert_equal {x a c} [r zsubset ztmp 4 a c z x sort asc]
            assert_equal {x a} [r zsubset ztmp 4 a c z x sort max 40]
            assert_equal {c a x} [r zsubset ztmp 4 a c z x sort desc]
            assert_equal {z x a c} [r zsubset ztmp 4 a c z x sort defaultscore 0]
            assert_equal {z x a} [r zsubset ztmp 4 a c z x sort max 40 defaultscore 0]
            assert_equal {x a} [r zsubset ztmp 4 a c z x sort max 40 defaultscore 80]
            assert_equal {c a x z} [r zsubset ztmp 4 a c z x sort desc defaultscore 0]
            assert_equal {z c a x} [r zsubset ztmp 4 a c z x sort desc defaultscore 80]
            assert_equal {x a} [r zsubset ztmp 4 a c z x sort limit 0 2]
            assert_equal {a c} [r zsubset ztmp 4 a c z x sort limit 1 2]
            assert_equal {a} [r zsubset ztmp 4 a c z x sort limit 1 2 max 40]
            assert_equal {c a} [r zsubset ztmp 4 a c z x sort desc limit 0 2]
            assert_equal {a x} [r zsubset ztmp 4 a c z x sort desc limit 1 2]
            assert_equal {w -10 x 10 c 50} [r zsubset ztmp 4 w c z x withscores sort]
            assert_equal {x 10 c 50} [r zsubset ztmp 4 w c z x withscores sort limit 1 2]
            assert_equal {c 50 x 10} [r zsubset ztmp 4 w c z x withscores sort desc limit 0 2]
        }

        test "ZSET sorting stresser - $encoding" {
            set delta 0
            for {set test 0} {$test < 2} {incr test} {
                unset -nocomplain auxarray
                array set auxarray {}
                set auxlist {}
                r del myzset
                for {set i 0} {$i < $elements} {incr i} {
                    if {$test == 0} {
                        set score [expr rand()]
                    } else {
                        set score [expr int(rand()*10)]
                    }
                    set auxarray($i) $score
                    r zadd myzset $score $i
                    # Random update
                    if {[expr rand()] < .2} {
                        set j [expr int(rand()*1000)]
                        if {$test == 0} {
                            set score [expr rand()]
                        } else {
                            set score [expr int(rand()*10)]
                        }
                        set auxarray($j) $score
                        r zadd myzset $score $j
                    }
                }
                foreach {item score} [array get auxarray] {
                    lappend auxlist [list $score $item]
                }
                set sorted [lsort -command zlistAlikeSort $auxlist]
                set auxlist {}
                foreach x $sorted {
                    lappend auxlist [lindex $x 1]
                }

                assert_encoding $encoding myzset
                set fromredis [r zrange myzset 0 -1]
                set delta 0
                for {set i 0} {$i < [llength $fromredis]} {incr i} {
                    if {[lindex $fromredis $i] != [lindex $auxlist $i]} {
                        incr delta
                    }
                }
            }
            assert_equal 0 $delta
        }

        test "ZRANGEBYSCORE fuzzy test, 100 ranges in $elements element sorted set - $encoding" {
            set err {}
            r del zset
            for {set i 0} {$i < $elements} {incr i} {
                r zadd zset [expr rand()] $i
            }

            assert_encoding $encoding zset
            for {set i 0} {$i < 100} {incr i} {
                set min [expr rand()]
                set max [expr rand()]
                if {$min > $max} {
                    set aux $min
                    set min $max
                    set max $aux
                }
                set low [r zrangebyscore zset -inf $min]
                set ok [r zrangebyscore zset $min $max]
                set high [r zrangebyscore zset $max +inf]
                set lowx [r zrangebyscore zset -inf ($min]
                set okx [r zrangebyscore zset ($min ($max]
                set highx [r zrangebyscore zset ($max +inf]

                if {[r zcount zset -inf $min] != [llength $low]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset $min $max] != [llength $ok]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset $max +inf] != [llength $high]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset -inf ($min] != [llength $lowx]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset ($min ($max] != [llength $okx]} {
                    append err "Error, len does not match zcount\n"
                }
                if {[r zcount zset ($max +inf] != [llength $highx]} {
                    append err "Error, len does not match zcount\n"
                }

                foreach x $low {
                    set score [r zscore zset $x]
                    if {$score > $min} {
                        append err "Error, score for $x is $score > $min\n"
                    }
                }
                foreach x $lowx {
                    set score [r zscore zset $x]
                    if {$score >= $min} {
                        append err "Error, score for $x is $score >= $min\n"
                    }
                }
                foreach x $ok {
                    set score [r zscore zset $x]
                    if {$score < $min || $score > $max} {
                        append err "Error, score for $x is $score outside $min-$max range\n"
                    }
                }
                foreach x $okx {
                    set score [r zscore zset $x]
                    if {$score <= $min || $score >= $max} {
                        append err "Error, score for $x is $score outside $min-$max open range\n"
                    }
                }
                foreach x $high {
                    set score [r zscore zset $x]
                    if {$score < $max} {
                        append err "Error, score for $x is $score < $max\n"
                    }
                }
                foreach x $highx {
                    set score [r zscore zset $x]
                    if {$score <= $max} {
                        append err "Error, score for $x is $score <= $max\n"
                    }
                }
            }
            assert_equal {} $err
        }

        test "ZSETs skiplist implementation backlink consistency test - $encoding" {
            set diff 0
            for {set j 0} {$j < $elements} {incr j} {
                r zadd myzset [expr rand()] "Element-$j"
                r zrem myzset "Element-[expr int(rand()*$elements)]"
            }

            assert_encoding $encoding myzset
            set l1 [r zrange myzset 0 -1]
            set l2 [r zrevrange myzset 0 -1]
            for {set j 0} {$j < [llength $l1]} {incr j} {
                if {[lindex $l1 $j] ne [lindex $l2 end-$j]} {
                    incr diff
                }
            }
            assert_equal 0 $diff
        }

        test "ZSETs ZRANK augmented skip list stress testing - $encoding" {
            set err {}
            r del myzset
            for {set k 0} {$k < 2000} {incr k} {
                set i [expr {$k % $elements}]
                if {[expr rand()] < .2} {
                    r zrem myzset $i
                } else {
                    set score [expr rand()]
                    r zadd myzset $score $i
                    assert_encoding $encoding myzset
                }

                set card [r zcard myzset]
                if {$card > 0} {
                    set index [randomInt $card]
                    set ele [lindex [r zrange myzset $index $index] 0]
                    set rank [r zrank myzset $ele]
                    if {$rank != $index} {
                        set err "$ele RANK is wrong! ($rank != $index)"
                        break
                    }
                }
            }
            assert_equal {} $err
        }
    }

    tags {"slow"} {
        stressers ziplist
        stressers skiplist
    }
}
