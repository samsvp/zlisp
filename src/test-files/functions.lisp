(def my-enumerate
  (fn [col]
    (let [total (count col)
          f (fn [n col total acc]
              (if (= n total)
                acc (f (+ n 1) col total (+ acc ((n (nth col n)))))))]
      (f 0 col total ()))))
