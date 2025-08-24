(def my-enumerate
  (fn [col]
    (let [total (count col)
          f (fn [n col total acc]
              (if (= n total)
                acc (f (+ n 1) col total (+ acc ((n (nth col n)))))))]
      (f 0 col total ()))))


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
