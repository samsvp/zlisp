(def enumerate
  (fn [col]
    (let [i (atom -1)]
      (map
        (fn [i] [v]
          (let [_ (swap! i (fn [a b] (+ a b)) 1)]
            ((deref i) v)))
        col))))


(defmacro infix [infixed]
  (list (nth infixed 1) (nth infixed 0) (nth infixed 2)))

(defmacro cond
  (fn [&xs]
    (if (> (count xs) 0)
        (list 'if (head xs)
              (if (> (count xs) 1)
                  (nth xs 1)
                  (throw "odd number of forms to cond"))
              (cons 'cond (tail (tail xs)))))))
