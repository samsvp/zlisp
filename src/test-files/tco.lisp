(do (def sum2 (fn [n acc] (if (= n 0) acc (sum2 (- n 1) (+ n acc))))) true)
(= (sum2 10 0) 55)

(do (def res2 nil) true)
(do (def res2 (sum2 10000 0)) true)
(= res2 50005000)

(do (def foo (fn [n] (if (= n 0) 0 (bar (- n 1))))) true)
(do (def bar (fn [n] (if (= n 0) 0 (foo (- n 1))))) true)
(= (foo 10000) 0)
