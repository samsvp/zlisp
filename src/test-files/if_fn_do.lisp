(= (list) ())
(= (list? (list)) true)
(= (list? nil) false)
(= (empty? (list)) true)
(= (empty? (list 1)) false)
(= (list 1 2 3) (1 2 3))
(= (count (list 1 2 3)) 3)
(= (count (list)) 0)
(= (count nil) 0)
(= (if (> (count (list 1 2 3)) 3) 89 78) 78)
(= (if (>= (count (list 1 2 3)) 3) 89 78) 89)

(= (if true 7 8) 7)
(= (if false 7 8) 8)
(= (if false 7 false) false)
(= (if true (+ 1 7) (+ 1 8)) 8)
(= (if false (+ 1 7) (+ 1 8)) 9)
(= (if nil 7 8) 8)
(= (if 0 7 8) 7)
(= (if (list) 7 8) 7)
(= (if (list 1 2 3) 7 8) 7)
(= (= (list) nil) false)

(= (if false (+ 1 7)) nil)
(= (if nil 8) nil)
(= (if nil 8 7) 7)
(= (if true (+ 1 7)) 8)

(= (= 2 1) false)
(= (= 1 1) true)
(= (= 1 2) false)
(= (= 1 (+ 1 1)) false)
(= (= 2 (+ 1 1)) true)

(= (> 2 1) true)
(= (> 1 1) false)
(= (> 1 2) false)

(= (>= 2 1) true)
(= (>= 1 1) true)
(= (>= 1 2) false)

(= (< 2 1) false)
(= (< 1 1) false)
(= (< 1 2) true)

(= (<= 2 1) false)
(= (<= 1 1) true)
(= (<= 1 2) true)

(= (= 1 1) true)
(= (= 0 0) true)
(= (= 1 0) false)

(= (= nil nil) true)
(= (= nil false) false)
(= (= nil true) false)
(= (= nil 0) false)
(= (= nil 1) false)
(= (= nil "") false)
(= (= nil ()) false)
(= (= nil []) false)

(= (= false nil) false)
(= (= false false) true)
(= (= false true) false)
(= (= false 0) false)
(= (= false 1) false)
(= (= false "") false)
(= (= false ()) false)

(= (= true nil) false)
(= (= true false) false)
(= (= true true) true)
(= (= true 0) false)
(= (= true 1) false)
(= (= true "") false)
(= (= true ()) false)

(= (= (list) (list)) true)
(= (= (list) ()) true)
(= (= (list 1 2) (list 1 2)) true)
(= (= (list 1) (list)) false)
(= (= (list) (list 1)) false)
(= (= 0 (list)) false)
(= (= (list) 0) false)
(= (= (list nil) (list)) false)


(= (+ 1 2) 3)
(= ( (fn [a b] (+ b a)) 3 4) 7)
(= ( (fn [] 4) ) 4)
(= ( (fn [] ()) ) ())

(= ( (fn [f x] (f x)) (fn [a] (+ 1 a)) 7) 8)

(= ( ( (fn [a] (fn [a] [b] (+ a b))) 5) 7) 12)

(do (def gen-plus5 (fn [] (fn [b] (+ 5 b)))) true)
(do (def plus5 (gen-plus5)) true)
(= (plus5 7) 12)

(do (def gen-plusX (fn [x] (fn [x] [b] (+ x b)))) true)
(do (def plus7 (gen-plusX 7)) true)
(= (plus7 8) 15)

(= (let [b 0 f (fn [b] [] b)] (let [b 1] (f))) 0)

(= ((let [b 0] (fn [b] [] b))) 0)

(= (do (def a 6) 7 (+ a 8)) 14)
(= a 6)

(do (def DO (fn [a] 7)) true)
(= (DO 3) 7)

(do (def sumdown (fn [N] (if (> N 0) (+ N (sumdown (- N 1))) 0))) true)
(= (sumdown 1) 1)
(= (sumdown 2) 3)
(= (sumdown 6) 21)

(do (def fib (fn [N] (if (= N 0) 1 (if (= N 1) 1 (+ (fib (- N 1)) (fib (- N 2))))))) true)
(= (fib 1) 1)
(= (fib 2) 2)
(= (fib 4) 5)

(= (let (f (fn [] x) x 3) (f)) 3)
(= (let (cst (fn [n] (if (= n 0) nil (cst (- n 1))))) (cst 1)) nil)
(= (let (f (fn [n] (if (= n 0) 0 (g (- n 1)))) g (fn [n] (f n))) (f 2)) 0)

(= (if "" 7 8) 7)

(= (= "" "") true)
(= (= "abc" "abc") true)
(= (= "abc" "") false)
(= (= "" "abc") false)
(= (= "abc" "def") false)
(= (= "abc" "ABC") false)
(= (= (list) "") false)
(= (= "" (list)) false)

(= (not false) true)
(= (not nil) true)
(= (not true) false)
(= (not "a") false)
(= (not 0) false)



(= (str) "")
(= (str "") "")
(= (str "abc") "abc")
(= (str "\"") "\"")
(= (str 1 "abc" 3) "1abc3")
(= (str "abc  def" "ghi jkl") "abc  defghi jkl")
(= (str "abc\ndef\nghi") "abc\ndef\nghi")
(= (str "abc\\def\\ghi") "abc\\def\\ghi")
(= (str (list)) "()")

(= (= :abc :abc) true)
(= (= :abc :def) false)
(= (= :abc ":abc") false)
(= (= (list :abc) (list :abc)) true)

(= (if [] 7 8) 7)

(= (str []) "[]")


(= (count [1 2 3]) 3)
(= (empty? [1 2 3]) false)
(= (empty? []) true)
(= (list? [4 5 6]) false)

(= (= [7 8] [7 8]) true)
(= (= [:abc] [:abc]) true)
(= (= (list 1) []) false)
(= (= [] [1]) false)
(= (= 0 []) false)
(= (= [] 0) false)
(= (= [] "") false)
(= (= "" []) false)

(= ( (fn [] 4) ) 4)
(= ( (fn [f x] (f x)) (fn [a] (+ 1 a)) 7) 8)
