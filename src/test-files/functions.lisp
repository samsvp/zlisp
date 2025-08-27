(defmacro defn
  (fn [&args]
    (let [fn-name (first args)
          body (rest args)]
      ('def fn-name (cons 'fn body)))))

(defn enumerate [col]
  "Returns a tuple containing the index and value of each item in the collection.
   e.g '(= (enumerate [5 9 10]) [(0 5) (1 9) (2 10)])'"
  ([col]
    (let [i (atom -1)]
      (map
        (fn [i] [v]
          (let [_ (swap! i (fn [a b] (+ a b)) 1)]
            ((deref i) v)))
        col))))

(defn infix [infixed]
  ((nth infixed 1) (nth infixed 0) (nth infixed 2)))

(defn cond
  [&xs]
  (if (> (count xs) 1)
    (if (first xs)
      (first (rest xs))
      (cond (rest (rest xs))))
    nil))

