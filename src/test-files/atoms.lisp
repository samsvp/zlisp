(do (def inc3 (fn [a] (+ 3 a))) true)
(do (def a (atom 2)) true)
(atom? a)
(= (atom? 1) false)

(= (deref a) 2)
(= (reset! a 3) 3)

(= (deref a) 3)

(= (swap! a inc3) 6)
(= (deref a) 6)

(= (swap! a (fn [a] a)) 6)

(= (swap! a (fn [a] (* 2 a))) 12)

(= (swap! a (fn [a b] (* a b)) 10) 120)

(= (swap! a + 3) 123)


(do (def b (atom 0)) true)
(do (swap! b + 1) (swap! b + 10) (swap! b + 100) true)
(= (deref b) 111)

(do (def inc-it (fn [a] (+ 1 a))) true)
(do (def atm (atom 7)) true)
(do (def f (fn [] (swap! atm inc-it))) true)
(= (f) 8)
(= (f) 9)

(do (def g (let (atm (atom 0)) (fn [atm] [] (deref atm)))) true)
(do (def atm (atom 1)) true)
(= (g) 0)
