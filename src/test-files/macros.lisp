(do (defmacro one (fn [] 1)) true)
(= (one) 1)
(do (defmacro two (fn [] 2)) true)
(= (two) 2)

(do (defmacro unless (fn [pred a b] `(if ~pred ~b ~a))) true)
(= (unless false 7 8) 7)
(= (unless true 7 8) 8)
(do (defmacro unless2 (fn [pred a b] (list 'if (list 'not pred) a b))) true)
(= (unless2 false 7 8) 7)
(= (unless2 true 7 8) 8)

(do (defmacro identity (fn [x] x)) true)
(= (let [a 123] (identity a)) 123)

(= () ())

(= `(1) (1))

(= (not (= 1 1)) false)
(= (not (= 1 2)) true)

(= (nth (list 1) 0) 1)
(= (nth (list 1 2) 1) 2)
(= (nth (list 1 2 nil) 2) nil)
(= (def x "x") "x")
(= (def x (nth (list 1 2) 2)) "x")
(= x "x")

(= (first (list)) nil)
(= (first (list 6)) 6)
(= (first (list 7 8 9)) 7)

(= (rest (list)) ())
(= (rest (list 6)) ())
(= (rest (list 7 8 9)) (8 9))

(= (cond) nil)
(= (cond true 7) 7)
(= (cond false 7) nil)
(= (cond true 7 true 8) 7)
(= (cond false 7 true 8) 8)
(= (cond false 7 false 8 "else" 9) 9)
(= (cond false 7 (= 2 2) 8 "else" 9) 8)
(= (cond false 7 false 8 false 9) nil)

(= (let (x (cond false "no" true "yes")) x) "yes")

(= (nth [1] 0) 1)
(= (nth [1 2] 1) 2)
(= (nth [1 2 nil] 2) nil)
(= (def x "x") "x")
(= (def x (nth [1 2] 2)) "x")
(= x "x")

(= (first []) nil)
(= (first nil) nil)
(= (first [10]) 10)
(= (first [10 11 12]) 10)
(= (rest []) ())
(= (rest nil) ())
(= (rest [10]) ())
(= (rest [10 11 12]) (11 12))
(= (rest (cons 10 [11 12])) (11 12))

(= (let [x (cond false "no" true "yes")] x) "yes")

(= (def x 2) 2)
(= (defmacro a (fn [] x)) (fn [] x))
(= (a) 2)
(= (let (x 3) (a)) 2)
