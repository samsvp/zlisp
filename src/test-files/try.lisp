(= (try 123 (catch e 456)) 123)
(= (try abc (catch exc nil)) nil)
(= (try (abc 1 2) (catch exc nil)) nil)

(= (try (nth () 1) (catch exc nil)) nil)
(= (try (list 1) (catch exc nil)) (1))

(= (try (throw "my exception") (catch exc (do (str "exc:" exc) 7))) 7)

(= (try (do (try "t1" (catch e "c1")) (throw "e1")) (catch e "c2")) "c2")
(= (try (try (throw "e1") (catch e (throw "e2"))) (catch e "c2")) "c2")

(= (try (map throw (list "my err")) (catch exc exc)) "ERROR: my err")

(= (symbol? 'abc) true)
(= (symbol? "abc") false)

(= (nil? nil) true)
(= (nil? false) false)
(= (nil? true) false)
(= (nil? ()) false)
(= (nil? 0) false)

(= (true? nil) false)
(= (true? false) false)
(= (true? true) true)
(= (true? 1) false)
(= (true? true?) false)

(= (false? nil) false)
(= (false? false) true)
(= (false? true) false)
(= (false? "") false)
(= (false? 0) false)
(= (false? ()) false)
(= (false? []) false)
(= (false? {}) false)
(= (false? nil) false)

(= (apply + (list 2 3)) 5)
(= (apply + 4 (list 5)) 9)
(= (apply list (list)) ())
(= (apply symbol? '((quote two))) true)

(= (apply (fn [a b] (+ a b)) (list 2 3)) 5)
(= (apply (fn [a b] (+ a b)) 4 (list 5)) 9)

(do (defmacro m (fn [a b] (+ a b))) (fn [a b] (+ a b)) true)
(= (apply m (list 2 3)) 5)
(= (apply m 4 (list 5)) 9)

(= (def nums (list 1 2 3)) (1 2 3))
(do (def double (fn [a] (* 2 a))) true)
(= (double 3) 6)
(= (map double nums) (2 4 6))
(= (map symbol? '(1 (quote two) "three")) (false true false))
(= () (map str ()))

(= (symbol? :abc) false)
(= (symbol? 'abc) true)
(= (symbol? "abc") false)
(= (symbol? (symbol "abc")) true)
(= (keyword? :abc) true)
(= (keyword? 'abc) false)
(= (keyword? "abc") false)
(= (keyword? "") false)
(= (keyword? (keyword "abc")) true)

(= (symbol "abc") 'abc)
(= (keyword "abc") :abc)

(= (apply + 4 [5]) 9)
(= (apply list []) ())
(= (apply (fn [a b] (+ a b)) [2 3]) 5)
(= (apply (fn [a b] (+ a b)) 4 [5]) 9)

(= (map (fn [a] (* 2 a)) [1 2 3]) [2 4 6])

(= (map (fn [&args] (list? args)) [1 2]) [true true])

(= (vector? [10 11]) true)
(= (vector? '(12 13)) false)
(= (vector 3 4 5) [3 4 5])
(= [] (vector))

(= (dict? {}) true)
(= (dict? '()) false)
(= (dict? []) false)
(= (dict? 'abc) false)
(= (dict? :abc) false)

(= (dict "a" 1) {"a" 1})
(= {"a" 1} {"a" 1})
(= (assoc {} "a" 1) {"a" 1})
(= (get (assoc (assoc {"a" 1 } "b" 2) "c" 3) "a") 1)
(= (def hm1 (dict)) {})
(= (dict? hm1) true)
(= (dict? 1) false)
(= (dict? "abc") false)

(= (get hm1 "a") nil)
(= (contains? hm1 "a") false)
(= (def hm2 (assoc hm1 "a" 1)) {"a" 1})
(= (get hm1 "a") nil)
(= (contains? hm1 "a") false)
(= (get hm2 "a") 1)
(= (contains? hm2 "a") true)

(= (keys hm1) ())
(= () (keys hm1))

(= (keys hm2) ("a"))

(= (keys {"1" 1}) ("1"))

(= (vals hm1) ())
(= () (vals hm1))
(= (vals hm2) (1))
(= (count (keys (assoc hm2 "b" 2 "c" 3))) 3)

(= (get {:abc 123} :abc) 123)
(= (contains? {:abc 123} :abc) true)
(= (contains? {:abcd 123} :abc) false)
(= (assoc {} :bcd 234) {:bcd 234})
(= (keyword? (nth (keys {:abc 123 :def 456}) 0)) true)
(= (keyword? (nth (vals {"a" :abc "b" :def}) 0)) true)

(= (def hm4 (assoc {:a 1 :b 2} :a 3 :c 1)) {:a 3 :b 2 :c 1})
(= (get hm4 :a) 3)
(= (get hm4 :b) 2)
(= (get hm4 :c) 1)

(= (contains? {:abc nil} :abc) true)
(= (assoc {} :bcd nil) {:bcd nil})

(= (str true "." false "." nil "." :keyw "." 'symb) "true.false.nil.:keyw.symb")

(= (apply (fn [&more] (list? more)) [1 2 3]) true)
(= (apply (fn [&more] (list? more)) []) true)
(= (apply (fn [a &more] (list? more)) [1]) true)

(= (try (throw (list 1 2 3)) (catch exc (do (str "err:" exc) 7))) 7)
(= (def hm3 (assoc hm2 "b" 2)) {"a" 1 "b" 2})
(= (count (keys hm3)) 2)
(= (count (vals hm3)) 2)
(= (dissoc hm3 "a") {"b" 2})
(= (dissoc hm3 "a" "b") {})
(= (dissoc hm3 "a" "b" "c") {})
(= (count (keys hm3)) 2)

(= (dissoc {:cde 345 :fgh 456} :cde) {:fgh 456})
(= (dissoc {:cde nil :fgh 456} :cde) {:fgh 456})
(= {} {})
(= {} (dict))
(= {:a 11 :b 22} (dict :b 22 :a 11))
(= {:a 11 :b [22 33]} (dict :b [22 33] :a 11))
(= {:a 11 :b {:c 33}} (dict :b {:c 33} :a 11))
(= {:a 11 :b 22} (dict :a 11 :b 22))
(= (= {:a 11 :b 22} (dict :a 11)) false)
(= (= {:a [11 22]} {:a (list 11 22)}) false)
(= (= {:a 11 :b 22} (list :a 11 :b 22)) false)
(= (= {} []) false)
(= (= [] {}) false)

(= (keyword :abc) :abc)
(= (keyword? (first (keys {":abc" 123 ":def" 456}))) false)

(do (def bar (fn [a] {:foo (get a :foo)})) true)
(= (bar {:foo 3}) {:foo 3})

(= (get {"abc" 1} :abc) nil)
(= (get {:abc 1} "abc") nil)
(= (contains? {"abc" 1} :abc) false)
(= (contains? {:abc 1} "abc") false)
(= (dissoc {"abc" 1 :abc 1} :abc) {"abc" 1})
(= (dissoc {"abc" 1 :abc 1} "abc") {:abc 1})

(= {:a 1 :a 2} {:a 2})
(= (keys {:a 1 :a 2}) (:a))
(= (dict :a 1 :a 2) {:a 2})
(= (keys (dict :a 1 :a 2)) (:a))
(= (assoc {:a 1} :a 2) {:a 2})
(= (keys (assoc {:a 1} :a 2)) (:a))

(= (def hm7 {:a 1}) {:a 1})
(= (assoc hm7 :a 2) {:a 2})
(= (get hm7 :a) 1)
